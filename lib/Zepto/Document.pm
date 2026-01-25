package Zepto::Document;
# Document: Buffer + undo/redo + dirty tracking + file metadata
# Provides high-level text editing operations

use strict;
use warnings;
use utf8;
use Zepto::Buffer;

# Undo grouping timeout in seconds (consecutive edits within this window are grouped)
use constant UNDO_GROUP_TIMEOUT => 1.0;

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
    }, $class;

    return $self;
}

# Load document from file
sub load {
    my ($class, $path) = @_;

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

    # Get file permissions
    my $permissions = (stat($path))[2] & 07777;

    return $class->new(
        text        => $content,
        path        => $path,
        line_ending => $line_ending,
        permissions => $permissions,
    );
}

# Save document to file
sub save {
    my ($self, $path) = @_;
    $path //= $self->{path};

    die "No path specified" unless defined $path;

    my $content = $self->{buffer}->text();

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

    return $deleted;
}

# Undo last action (or group of actions)
sub undo {
    my ($self) = @_;

    return 0 unless @{$self->{undo_stack}};

    my $action = pop @{$self->{undo_stack}};

    if ($action->{type} eq 'insert') {
        # Undo insert: delete the text
        $self->{buffer}->delete($action->{pos}, CORE::length($action->{text}));
    }
    elsif ($action->{type} eq 'delete') {
        # Undo delete: re-insert the text
        $self->{buffer}->insert($action->{pos}, $action->{text});
    }
    elsif ($action->{type} eq 'replace') {
        # Undo replace: delete new text, insert old text
        $self->{buffer}->delete($action->{pos}, CORE::length($action->{new_text}));
        $self->{buffer}->insert($action->{pos}, $action->{old_text});
    }

    push @{$self->{redo_stack}}, $action;

    # Mark clean if we've undone everything
    $self->{dirty} = @{$self->{undo_stack}} > 0;

    # Break grouping
    $self->{_last_edit_type} = '';

    return 1;
}

# Redo last undone action
sub redo {
    my ($self) = @_;

    return 0 unless @{$self->{redo_stack}};

    my $action = pop @{$self->{redo_stack}};

    if ($action->{type} eq 'insert') {
        # Redo insert: insert the text again
        $self->{buffer}->insert($action->{pos}, $action->{text});
    }
    elsif ($action->{type} eq 'delete') {
        # Redo delete: delete the text again
        $self->{buffer}->delete($action->{pos}, CORE::length($action->{text}));
    }
    elsif ($action->{type} eq 'replace') {
        # Redo replace: delete old text, insert new text
        $self->{buffer}->delete($action->{pos}, CORE::length($action->{old_text}));
        $self->{buffer}->insert($action->{pos}, $action->{new_text});
    }

    push @{$self->{undo_stack}}, $action;
    $self->{dirty} = 1;

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

1;
