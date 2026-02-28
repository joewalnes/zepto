package Zepto::Document;
# Document: Buffer + undo/redo + dirty tracking + file metadata + VCS integration
# Provides high-level text editing operations

use strict;
use warnings;
use utf8;
use Zepto::Buffer;
use Zepto::VCS::Provider;
use Zepto::VCS::Git;  # Ensure Git provider is registered
use Zepto::Diff;

# Undo grouping timeout in seconds (consecutive edits within this window are grouped)
use constant UNDO_GROUP_TIMEOUT => 1.0;

# VCS diff debounce delay in seconds
use constant VCS_DIFF_DEBOUNCE => 0.3;

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
        buffer       => Zepto::Buffer->new($opts{text} // ''),
        path         => $opts{path},
        line_ending  => $opts{line_ending} // "\n",  # LF default
        permissions  => $opts{permissions},
        dirty        => 0,
        undo_stack   => [],
        redo_stack   => [],
        # For undo grouping
        _last_edit_time => 0,
        _last_edit_type => '',
        _last_edit_pos  => -1,
        _undo_group     => undef,
        # VCS integration
        _vcs_provider   => undef,
        _vcs_base       => undef,  # Cached HEAD content
        _vcs_diff       => undef,  # { added => [], modified => [], deleted => [] }
        _vcs_dirty      => 0,      # Buffer changed since last diff
        _vcs_last_diff  => 0,      # Timestamp of last diff computation
    }, $class;

    # Detect VCS if path is provided (skip_vcs defers this for preview tabs)
    if (defined $opts{path} && !$opts{skip_vcs}) {
        $self->_init_vcs();
    }

    return $self;
}

# Load document from file
# Options: skip_vcs => 1 to defer VCS initialization (for preview tabs)
sub load {
    my ($class, $path, %opts) = @_;

    open my $fh, '<:encoding(UTF-8)', $path
        or die "Cannot open $path: $!";

    local $/;
    my $content = <$fh>;
    close $fh;

    # Detect line ending style
    my $crlf_count = () = $content =~ /\r\n/g;
    my $lf_count = () = $content =~ /(?<!\r)\n/g;
    my $line_ending = $crlf_count > $lf_count ? "\r\n" : "\n";

    # Normalize to LF internally
    $content =~ s/\r\n/\n/g;

    # Strip trailing newline for editing (save adds it back)
    $content =~ s/\n$//;

    # Get file permissions
    my $permissions = (stat($path))[2] & 07777;

    return $class->new(
        text        => $content,
        path        => $path,
        line_ending => $line_ending,
        permissions => $permissions,
        ($opts{skip_vcs} ? (skip_vcs => 1) : ()),
    );
}

# Initialize VCS for a document that was loaded with skip_vcs
sub init_vcs {
    my ($self) = @_;
    return if $self->{_vcs_provider};  # already initialized
    $self->_init_vcs() if defined $self->{path};
}

# Save document to file
sub save {
    my ($self, $path) = @_;
    $path //= $self->{path};

    die "No path specified" unless defined $path;

    my $content = $self->{buffer}->text();

    # Ensure file ends with newline (POSIX convention)
    if (length($content) > 0 && $content !~ /\n$/) {
        $content .= "\n";
    }

    # Convert to target line ending
    if ($self->{line_ending} eq "\r\n") {
        $content =~ s/\n/\r\n/g;
    }

    # Atomic save: write to temp file, then rename
    my $temp_path = "$path.zepto.tmp.$$";

    eval {
        open my $fh, '>:encoding(UTF-8)', $temp_path
            or die "Cannot create temp file $temp_path: $!";
        print $fh $content;
        close $fh or die "Cannot close temp file: $!";

        # Preserve permissions if we have them
        if (defined $self->{permissions}) {
            chmod $self->{permissions}, $temp_path;
        }

        rename $temp_path, $path
            or die "Cannot rename $temp_path to $path: $!";
    };

    if ($@) {
        unlink $temp_path;  # Clean up on error
        die $@;
    }

    $self->{path} = $path;
    $self->{dirty} = 0;

    return 1;
}

# Buffer accessors
sub buffer { $_[0]->{buffer} }
sub text { $_[0]->{buffer}->text() }
sub length { $_[0]->{buffer}->length() }
sub line_count { $_[0]->{buffer}->line_count() }
sub get_line { $_[0]->{buffer}->get_line($_[1]) }
sub get_line_content { $_[0]->{buffer}->get_line_content($_[1]) }
sub line_length { $_[0]->{buffer}->line_length($_[1]) }
sub get_text { shift->{buffer}->get_text(@_) }
sub offset_to_line_col { shift->{buffer}->offset_to_line_col(@_) }
sub line_col_to_offset { shift->{buffer}->line_col_to_offset(@_) }
sub line_start_offset { shift->{buffer}->line_start_offset(@_) }

# Document metadata
sub path { $_[0]->{path} }
sub set_path { $_[0]->{path} = $_[1] }
sub line_ending { $_[0]->{line_ending} }
sub set_line_ending { $_[0]->{line_ending} = $_[1] }
sub is_dirty { $_[0]->{dirty} }

# Display name for UI
sub display_name {
    my ($self) = @_;
    return defined $self->{path} ? $self->{path} : '[untitled]';
}

sub filename {
    my ($self) = @_;
    return '[untitled]' unless defined $self->{path};
    my $name = $self->{path};
    $name =~ s{.*/}{};  # Strip directory
    return $name;
}

# ============================================================================
# Edit operations with undo support
# ============================================================================

# Internal: record an undo action
sub _push_undo {
    my ($self, $action) = @_;

    my $now = time();
    my $should_group = 0;

    if ($self->{_undo_group}) {
        push @{$self->{_undo_group}}, $action;
        $self->{redo_stack} = [];
        $self->{dirty} = 1;
        $self->{_vcs_dirty} = 1;
        $self->{_last_edit_time} = $now;
        $self->{_last_edit_type} = $action->{type};
        $self->{_last_edit_pos} = $action->{pos};
        return;
    }

    # Group consecutive single-char inserts/deletes at adjacent positions
    if (@{$self->{undo_stack}} > 0) {
        my $last = $self->{undo_stack}[-1];

        # Same operation type, within timeout, adjacent position
        if ($action->{type} eq $last->{type} &&
            ($now - $self->{_last_edit_time}) < UNDO_GROUP_TIMEOUT &&
            CORE::length($action->{text}) == 1 &&
            CORE::length($last->{text}) < 100)  # Don't make groups too large
        {
            if ($action->{type} eq 'insert') {
                # Insert: new position should be at end of last insert
                if ($action->{pos} == $last->{pos} + CORE::length($last->{text})) {
                    $should_group = 1;
                    $last->{text} .= $action->{text};
                }
            }
            elsif ($action->{type} eq 'delete') {
                # Backspace: new position should be just before last delete
                if ($action->{pos} == $last->{pos} - 1) {
                    $should_group = 1;
                    $last->{text} = $action->{text} . $last->{text};
                    $last->{pos} = $action->{pos};
                }
                # Forward delete: same position
                elsif ($action->{pos} == $last->{pos}) {
                    $should_group = 1;
                    $last->{text} .= $action->{text};
                }
            }
        }
    }

    unless ($should_group) {
        push @{$self->{undo_stack}}, $action;
    }

    # Clear redo stack on new edit
    $self->{redo_stack} = [];

    $self->{_last_edit_time} = $now;
    $self->{_last_edit_type} = $action->{type};
    $self->{_last_edit_pos} = $action->{pos};
    $self->{dirty} = 1;
    $self->{_vcs_dirty} = 1;  # Mark VCS diff as stale
}

# Insert text at position
sub insert {
    my ($self, $pos, $text) = @_;
    return if !defined($text) || $text eq '';

    $self->{buffer}->insert($pos, $text);

    $self->_push_undo({
        type => 'insert',
        pos  => $pos,
        text => $text,
    });

    return CORE::length($text);
}

# Delete text at position
sub delete {
    my ($self, $pos, $len) = @_;
    return '' if !defined($len) || $len <= 0;

    my $deleted = $self->{buffer}->delete($pos, $len);

    if ($deleted ne '') {
        $self->_push_undo({
            type => 'delete',
            pos  => $pos,
            text => $deleted,
        });
    }

    return $deleted;
}

# Replace text
sub replace {
    my ($self, $start, $end, $text) = @_;

    # Break grouping for complex operations
    $self->{_last_edit_type} = '';

    my $deleted = $self->{buffer}->delete($start, $end - $start);
    $self->{buffer}->insert($start, $text);

    # Record as a single compound action
    push @{$self->{undo_stack}}, {
        type => 'replace',
        pos  => $start,
        old_text => $deleted,
        new_text => $text,
    };

    $self->{redo_stack} = [];
    $self->{dirty} = 1;
    $self->{_vcs_dirty} = 1;  # Mark VCS diff as stale

    return $deleted;
}

# Undo last action (or group of actions)
sub undo {
    my ($self) = @_;

    return 0 unless @{$self->{undo_stack}};

    my $action = pop @{$self->{undo_stack}};

    if ($action->{type} eq 'group') {
        for my $a (reverse @{$action->{actions}}) {
            $self->_apply_action($a, 'undo');
        }
    } else {
        $self->_apply_action($action, 'undo');
    }

    push @{$self->{redo_stack}}, $action;

    # Mark clean if we've undone everything
    $self->{dirty} = @{$self->{undo_stack}} > 0;
    $self->{_vcs_dirty} = 1;  # Mark VCS diff as stale

    # Break grouping
    $self->{_last_edit_type} = '';

    return 1;
}

# Redo last undone action
sub redo {
    my ($self) = @_;

    return 0 unless @{$self->{redo_stack}};

    my $action = pop @{$self->{redo_stack}};

    if ($action->{type} eq 'group') {
        for my $a (@{$action->{actions}}) {
            $self->_apply_action($a, 'redo');
        }
    } else {
        $self->_apply_action($action, 'redo');
    }

    push @{$self->{undo_stack}}, $action;
    $self->{dirty} = 1;
    $self->{_vcs_dirty} = 1;  # Mark VCS diff as stale

    # Break grouping
    $self->{_last_edit_type} = '';

    return 1;
}

# Check if undo/redo is available
sub can_undo { @{$_[0]->{undo_stack}} > 0 }
sub can_redo { @{$_[0]->{redo_stack}} > 0 }

# Clear undo/redo history
sub clear_history {
    my ($self) = @_;
    $self->{undo_stack} = [];
    $self->{redo_stack} = [];
}

# Mark document as clean (after save)
sub mark_clean {
    my ($self) = @_;
    $self->{dirty} = 0;
}

# Force break undo grouping (e.g., when cursor moves)
sub break_undo_group {
    my ($self) = @_;
    $self->{_last_edit_type} = '';
}

sub begin_undo_group {
    my ($self) = @_;
    return if $self->{_undo_group};
    $self->{_undo_group} = [];
    $self->{_last_edit_type} = '';
}

sub end_undo_group {
    my ($self) = @_;
    my $group = $self->{_undo_group};
    $self->{_undo_group} = undef;
    return unless $group && @$group;

    push @{$self->{undo_stack}}, { type => 'group', actions => $group };
    $self->{redo_stack} = [];
    $self->{dirty} = 1;
    $self->{_vcs_dirty} = 1;
    $self->{_last_edit_type} = '';
}

sub _apply_action {
    my ($self, $action, $direction) = @_;

    if ($action->{type} eq 'insert') {
        if ($direction eq 'undo') {
            $self->{buffer}->delete($action->{pos}, CORE::length($action->{text}));
        } else {
            $self->{buffer}->insert($action->{pos}, $action->{text});
        }
    }
    elsif ($action->{type} eq 'delete') {
        if ($direction eq 'undo') {
            $self->{buffer}->insert($action->{pos}, $action->{text});
        } else {
            $self->{buffer}->delete($action->{pos}, CORE::length($action->{text}));
        }
    }
    elsif ($action->{type} eq 'replace') {
        if ($direction eq 'undo') {
            $self->{buffer}->delete($action->{pos}, CORE::length($action->{new_text}));
            $self->{buffer}->insert($action->{pos}, $action->{old_text});
        } else {
            $self->{buffer}->delete($action->{pos}, CORE::length($action->{old_text}));
            $self->{buffer}->insert($action->{pos}, $action->{new_text});
        }
    }
}

# ============================================================================
# VCS Integration
# ============================================================================

# Initialize VCS provider for this document
sub _init_vcs {
    my ($self) = @_;
    return unless defined $self->{path};

    $self->{_vcs_provider} = Zepto::VCS::Provider->detect($self->{path});

    if ($self->{_vcs_provider}) {
        # Get base content from HEAD
        $self->{_vcs_base} = $self->{_vcs_provider}->get_head_content($self->{path});
        # Compute initial diff
        $self->_compute_vcs_diff();
    }
}

# Check if VCS is available for this document
sub has_vcs {
    my ($self) = @_;
    return defined $self->{_vcs_provider};
}

# Get VCS provider name (e.g., "git")
sub vcs_name {
    my ($self) = @_;
    return $self->{_vcs_provider} ? $self->{_vcs_provider}->name : undef;
}

# Mark VCS diff as needing recomputation
sub _mark_vcs_dirty {
    my ($self) = @_;
    $self->{_vcs_dirty} = 1;
}

# Compute VCS diff (call after edits, debounced)
sub _compute_vcs_diff {
    my ($self) = @_;
    return unless $self->{_vcs_provider};

    my $current_text = $self->{buffer}->text();
    $self->{_vcs_diff} = Zepto::Diff->diff($self->{_vcs_base}, $current_text);
    $self->{_vcs_dirty} = 0;
    $self->{_vcs_last_diff} = time();
}

# Update VCS diff if needed (debounced)
# Call this periodically (e.g., on idle or before render)
sub update_vcs_diff {
    my ($self) = @_;
    return unless $self->{_vcs_provider};

    # Check if HEAD changed (e.g., commit in another window)
    if ($self->{_vcs_provider}->head_changed()) {
        $self->{_vcs_provider}->invalidate_cache($self->{path});
        $self->{_vcs_base} = $self->{_vcs_provider}->get_head_content($self->{path});
        $self->{_vcs_base_lines} = undef;
        $self->{_vcs_dirty} = 1;  # Force recompute
    }

    return unless $self->{_vcs_dirty};

    my $now = time();
    if ($now - $self->{_vcs_last_diff} >= VCS_DIFF_DEBOUNCE) {
        $self->_compute_vcs_diff();
    }
}

# Force immediate VCS diff recomputation
sub refresh_vcs_diff {
    my ($self) = @_;
    return unless $self->{_vcs_provider};
    $self->_compute_vcs_diff();
}

# Get VCS deletion status for a specific line (0-indexed)
# Returns: 'above', 'below', or undef
# Used for column 1 of the two-column VCS gutter
sub vcs_deletion_status {
    my ($self, $line) = @_;
    return undef unless $self->{_vcs_diff};

    my $diff = $self->{_vcs_diff};

    # deleted array contains line indices AFTER which deletions occurred
    for my $l (@{$diff->{deleted}}) {
        # Line $l has deletion after it (show lower block ▗)
        return 'below' if $l == $line;
        # Line $l+1 has deletion before it (show upper block ▝)
        return 'above' if $l + 1 == $line;
    }

    return undef;
}

# Get VCS change status for a specific line (0-indexed)
# Returns: 'added', 'modified', or undef
sub vcs_change_status {
    my ($self, $line) = @_;
    return undef unless $self->{_vcs_diff};

    my $diff = $self->{_vcs_diff};

    # Check if line is added
    for my $l (@{$diff->{added}}) {
        return 'added' if $l == $line;
    }

    # Check if line is modified
    for my $l (@{$diff->{modified}}) {
        return 'modified' if $l == $line;
    }

    # Check if line is whitespace-only modified
    if ($diff->{modified_whitespace}) {
        for my $l (@{$diff->{modified_whitespace}}) {
            return 'modified_whitespace' if $l == $line;
        }
    }

    return undef;
}

# Legacy wrapper for compatibility - returns first applicable status
sub vcs_line_status {
    my ($self, $line) = @_;
    return $self->vcs_deletion_status($line) ? 'deleted_' . $self->vcs_deletion_status($line)
         : $self->vcs_change_status($line);
}

# Get full VCS diff data (for advanced use)
sub vcs_diff {
    my ($self) = @_;
    return $self->{_vcs_diff};
}

# Invalidate VCS cache (call after save to refresh base content)
sub invalidate_vcs_cache {
    my ($self) = @_;
    return unless $self->{_vcs_provider};

    $self->{_vcs_provider}->invalidate_cache($self->{path});
    $self->{_vcs_base} = $self->{_vcs_provider}->get_head_content($self->{path});
    $self->{_vcs_base_lines} = undef;
    $self->_compute_vcs_diff();
}

# Get base (HEAD) text split into lines (cached)
sub vcs_base_lines {
    my ($self) = @_;
    return [] unless defined $self->{_vcs_base};
    $self->{_vcs_base_lines} //= [split(/\n/, $self->{_vcs_base}, -1)];
    return $self->{_vcs_base_lines};
}

# Get enriched hunk data from the diff result
sub vcs_hunks {
    my ($self) = @_;
    return $self->{_vcs_diff} ? ($self->{_vcs_diff}{hunks} // []) : [];
}

# Find the hunk index for a given document line (0-indexed)
# Returns the hunk index if the line has a VCS marker, undef otherwise
sub vcs_hunk_at_line {
    my ($self, $doc_line) = @_;
    my $hunks = $self->vcs_hunks();

    for my $i (0 .. $#$hunks) {
        my $h = $hunks->[$i];

        # Check if doc_line is in this hunk's current_lines
        for my $cl (@{$h->{current_lines}}) {
            return $i if $cl == $doc_line;
        }

        # For deletion hunks, check the marker position
        if ($h->{type} eq 'deleted') {
            my $marker;
            if ($h->{prev_curr_line} == -1) {
                $marker = 0;
            } elsif (!defined $h->{next_curr_line}) {
                $marker = $self->line_count() > 0 ? $self->line_count() - 1 : 0;
            } else {
                $marker = $h->{prev_curr_line};
            }
            return $i if $marker == $doc_line || ($marker + 1) == $doc_line;
        }
    }

    return undef;
}

1;
