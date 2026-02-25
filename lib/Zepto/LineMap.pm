package Zepto::LineMap;
# =============================================================================
# LineMap: Maps display rows to document lines for inline diff expansion
# =============================================================================
#
# When VCS diff hunks are expanded inline, "old" (base) lines are inserted
# into the display between document lines. This module is the single source
# of truth for the mapping between display rows and document content.
#
# Display row types:
#   { type => 'doc', line => N }                     # Normal document line
#   { type => 'doc', line => N, hunk_idx => H }      # Doc line in expanded hunk (green bg)
#   { type => 'old', base_line => N, hunk_idx => H } # Base line (red bg, read-only)
#
# =============================================================================

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        doc_line_count => $args{doc_line_count} // 0,
        hunks          => $args{hunks} // [],
        _expanded      => {},       # hunk_idx => 1
        _display_map   => undef,    # Cached: [entry, ...]
        _doc_to_display => undef,   # Cached: { doc_line => display_row }
        _dirty         => 1,
    }, $class;
    return $self;
}

# ============================================================================
# Hunk expansion state
# ============================================================================

sub toggle_hunk {
    my ($self, $hunk_idx) = @_;
    if ($self->{_expanded}{$hunk_idx}) {
        delete $self->{_expanded}{$hunk_idx};
    } else {
        # Only one hunk can be expanded at a time
        %{$self->{_expanded}} = ();
        $self->{_expanded}{$hunk_idx} = 1;
    }
    $self->{_dirty} = 1;
}

sub is_expanded {
    my ($self, $hunk_idx) = @_;
    return $self->{_expanded}{$hunk_idx} ? 1 : 0;
}

sub has_expanded_hunks {
    my ($self) = @_;
    return scalar keys %{$self->{_expanded}} > 0;
}

sub collapse_all {
    my ($self) = @_;
    $self->{_expanded} = {};
    $self->{_dirty} = 1;
}

sub invalidate {
    my ($self) = @_;
    $self->{_dirty} = 1;
}

# Update hunks and doc line count (call when diff is recomputed)
sub update {
    my ($self, %args) = @_;
    $self->{doc_line_count} = $args{doc_line_count} if exists $args{doc_line_count};
    $self->{hunks} = $args{hunks} if exists $args{hunks};
    # Collapse all — hunks may have shifted
    $self->{_expanded} = {};
    $self->{_dirty} = 1;
}

# ============================================================================
# Display map building
# ============================================================================

sub _ensure_built {
    my ($self) = @_;
    return unless $self->{_dirty};
    $self->_rebuild();
}

sub _rebuild {
    my ($self) = @_;

    my @map;
    my %doc_to_display;
    my $hunks = $self->{hunks};
    my $doc_count = $self->{doc_line_count};

    # Build index: for each hunk, determine where old lines insert
    # Modified/deleted hunks: old lines go before current_lines[0] (or at deletion point)
    # Added hunks: no old lines, but current_lines get green highlight
    my @hunk_inserts;  # [{at_doc_line => N, hunk_idx => N, old_lines => [...], current_set => {}}]

    for my $i (0 .. $#$hunks) {
        next unless $self->{_expanded}{$i};
        my $h = $hunks->[$i];

        # Build set of current lines for green highlighting
        my %current_set;
        $current_set{$_} = 1 for @{$h->{current_lines}};

        if ($h->{type} eq 'modified') {
            # Old lines go before the first current line
            my $insert_before = $h->{current_lines}[0];
            push @hunk_inserts, {
                at_doc_line => $insert_before,
                hunk_idx    => $i,
                old_lines   => $h->{base_lines},
                current_set => \%current_set,
            };
        }
        elsif ($h->{type} eq 'deleted') {
            # Old lines go after prev_curr_line (before next_curr_line)
            my $insert_before;
            if ($h->{prev_curr_line} == -1) {
                $insert_before = 0;  # Before first line
            } elsif (!defined $h->{next_curr_line}) {
                $insert_before = $doc_count;  # After last line (sentinel)
            } else {
                $insert_before = $h->{next_curr_line};
            }
            push @hunk_inserts, {
                at_doc_line => $insert_before,
                hunk_idx    => $i,
                old_lines   => $h->{base_lines},
                current_set => {},
            };
        }
        elsif ($h->{type} eq 'added') {
            # No old lines, but mark current lines for green highlight
            push @hunk_inserts, {
                at_doc_line => -1,  # Sentinel — no insertion point
                hunk_idx    => $i,
                old_lines   => [],
                current_set => \%current_set,
            };
        }
    }

    # Sort by insertion point so we can process in order
    @hunk_inserts = sort { $a->{at_doc_line} <=> $b->{at_doc_line} } @hunk_inserts;

    # Build combined current_set for O(1) lookup: doc_line => hunk_idx
    my %green_lines;
    for my $hi (@hunk_inserts) {
        for my $cl (keys %{$hi->{current_set}}) {
            $green_lines{$cl} = $hi->{hunk_idx};
        }
    }

    # Walk through doc lines, inserting old lines at the right positions
    my $insert_idx = 0;  # Next hunk_insert to process

    for my $doc_line (0 .. $doc_count - 1) {
        # Insert old lines from any hunks that trigger before this doc line
        while ($insert_idx < @hunk_inserts &&
               $hunk_inserts[$insert_idx]{at_doc_line} == $doc_line &&
               @{$hunk_inserts[$insert_idx]{old_lines}} > 0) {
            my $hi = $hunk_inserts[$insert_idx];
            for my $bl (@{$hi->{old_lines}}) {
                push @map, { type => 'old', base_line => $bl, hunk_idx => $hi->{hunk_idx} };
            }
            $insert_idx++;
        }

        # Skip non-inserting entries (added hunks with at_doc_line == -1 or already processed)
        while ($insert_idx < @hunk_inserts &&
               ($hunk_inserts[$insert_idx]{at_doc_line} < $doc_line ||
                $hunk_inserts[$insert_idx]{at_doc_line} == $doc_line &&
                @{$hunk_inserts[$insert_idx]{old_lines}} == 0)) {
            $insert_idx++;
        }

        # Emit the doc line entry
        $doc_to_display{$doc_line} = scalar @map;
        my $entry = { type => 'doc', line => $doc_line };
        if (exists $green_lines{$doc_line}) {
            $entry->{hunk_idx} = $green_lines{$doc_line};
        }
        push @map, $entry;
    }

    # Handle old lines that go after the last doc line (deletion at end)
    while ($insert_idx < @hunk_inserts) {
        my $hi = $hunk_inserts[$insert_idx];
        if (@{$hi->{old_lines}} > 0) {
            for my $bl (@{$hi->{old_lines}}) {
                push @map, { type => 'old', base_line => $bl, hunk_idx => $hi->{hunk_idx} };
            }
        }
        $insert_idx++;
    }

    $self->{_display_map} = \@map;
    $self->{_doc_to_display} = \%doc_to_display;
    $self->{_dirty} = 0;
}

# ============================================================================
# Public query API
# ============================================================================

sub total_display_rows {
    my ($self) = @_;
    $self->_ensure_built();
    return scalar @{$self->{_display_map}};
}

sub display_entry {
    my ($self, $display_row) = @_;
    $self->_ensure_built();
    return undef if $display_row < 0 || $display_row >= @{$self->{_display_map}};
    return $self->{_display_map}[$display_row];
}

sub doc_line_to_display {
    my ($self, $doc_line) = @_;
    $self->_ensure_built();
    return $self->{_doc_to_display}{$doc_line} // $doc_line;
}

# Count of "old" display rows inserted before a given doc line
sub extra_rows_before {
    my ($self, $doc_line) = @_;
    $self->_ensure_built();
    my $display_row = $self->{_doc_to_display}{$doc_line} // $doc_line;
    return $display_row - $doc_line;
}

# Get visible entries for a viewport.
# $scroll_line: first visible document line
# $height: number of screen rows available
# Returns arrayref of entry hashrefs (may include old and doc entries)
# Get the effective start display row for a scroll_line.
# Backs up to include old lines inserted before scroll_line (they belong to that viewport position).
sub scroll_display_start {
    my ($self, $scroll_line) = @_;
    $self->_ensure_built();

    my $start_display = $self->{_doc_to_display}{$scroll_line} // $scroll_line;
    my $map = $self->{_display_map};

    # Back up to include old lines inserted before scroll_line
    while ($start_display > 0 && $map->[$start_display - 1]{type} eq 'old') {
        $start_display--;
    }

    return $start_display;
}

sub visible_entries {
    my ($self, $scroll_line, $height) = @_;
    $self->_ensure_built();

    my $start_display = $self->scroll_display_start($scroll_line);
    my $map = $self->{_display_map};
    my $end = $start_display + $height;
    $end = scalar @$map if $end > scalar @$map;

    return [@{$map}[$start_display .. $end - 1]];
}

1;
