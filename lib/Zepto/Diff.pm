package Zepto::Diff;
# =============================================================================
# Diff: Line-based diff algorithm for VCS gutter indicators
# =============================================================================
#
# Implements the Myers diff algorithm to compare two texts line-by-line.
# Returns change information suitable for rendering gutter indicators.
#
# Output format:
#   {
#       added               => [line_numbers],  # Lines new in current (green)
#       modified            => [line_numbers],  # Lines changed from base (yellow)
#       modified_whitespace => [line_numbers],  # Lines with whitespace-only changes (dim yellow)
#       deleted             => [line_numbers],  # Lines AFTER which deletions occurred (red)
#   }
#
# Line numbers are 0-indexed (matching internal buffer representation).
# =============================================================================

use strict;
use warnings;
use utf8;

# =============================================================================
# Public API
# =============================================================================

# Compare base text against current text
# Returns hashref with added/modified/deleted arrays
sub diff {
    my ($class, $base_text, $current_text) = @_;

    # Handle edge cases
    return { added => [], modified => [], modified_whitespace => [], deleted => [], hunks => [] }
        if !defined($base_text) && !defined($current_text);

    # If no base, all current lines are additions
    if (!defined($base_text) || $base_text eq '') {
        my @lines = defined($current_text) ? split(/\n/, $current_text, -1) : ();
        return {
            added               => [0 .. $#lines],
            modified            => [],
            modified_whitespace => [],
            deleted             => [],
            hunks               => [],
        };
    }

    # If no current, everything was deleted
    if (!defined($current_text) || $current_text eq '') {
        return {
            added               => [],
            modified            => [],
            modified_whitespace => [],
            deleted             => [0],  # Deletion at start
            hunks               => [],
        };
    }

    # Split into lines
    my @base_lines = split(/\n/, $base_text, -1);
    my @current_lines = split(/\n/, $current_text, -1);

    # Run Myers diff
    my @edits = $class->_myers_diff(\@base_lines, \@current_lines);

    # Convert edit script to gutter indicators
    return $class->_edits_to_indicators(\@edits, \@base_lines, \@current_lines);
}

# =============================================================================
# Myers Diff Algorithm
# =============================================================================

# Myers diff implementation
# Returns list of edit operations: [op, base_line, current_line]
#   op: 'equal', 'insert', 'delete'
sub _myers_diff {
    my ($class, $base, $current) = @_;

    my $n = scalar(@$base);
    my $m = scalar(@$current);

    # Optimization: handle common prefix
    my $prefix_len = 0;
    while ($prefix_len < $n && $prefix_len < $m &&
           $base->[$prefix_len] eq $current->[$prefix_len]) {
        $prefix_len++;
    }

    # Optimization: handle common suffix
    my $suffix_len = 0;
    while ($suffix_len < ($n - $prefix_len) &&
           $suffix_len < ($m - $prefix_len) &&
           $base->[$n - 1 - $suffix_len] eq $current->[$m - 1 - $suffix_len]) {
        $suffix_len++;
    }

    # Build edit script for prefix
    my @edits;
    for my $i (0 .. $prefix_len - 1) {
        push @edits, ['equal', $i, $i];
    }

    # Run Myers on the middle portion
    my $base_start = $prefix_len;
    my $base_end = $n - $suffix_len;
    my $curr_start = $prefix_len;
    my $curr_end = $m - $suffix_len;

    my @base_mid = @{$base}[$base_start .. $base_end - 1];
    my @curr_mid = @{$current}[$curr_start .. $curr_end - 1];

    if (@base_mid || @curr_mid) {
        my @mid_edits = $class->_myers_core(\@base_mid, \@curr_mid);

        # Adjust line numbers back to original positions
        for my $edit (@mid_edits) {
            $edit->[1] += $base_start if defined $edit->[1];
            $edit->[2] += $curr_start if defined $edit->[2];
            push @edits, $edit;
        }
    }

    # Build edit script for suffix
    for my $i (0 .. $suffix_len - 1) {
        my $base_idx = $n - $suffix_len + $i;
        my $curr_idx = $m - $suffix_len + $i;
        push @edits, ['equal', $base_idx, $curr_idx];
    }

    return @edits;
}

# Core Myers algorithm (on potentially shorter arrays after prefix/suffix removal)
sub _myers_core {
    my ($class, $base, $current) = @_;

    my $n = scalar(@$base);
    my $m = scalar(@$current);

    return () if $n == 0 && $m == 0;

    # All insertions
    if ($n == 0) {
        return map { ['insert', undef, $_] } (0 .. $m - 1);
    }

    # All deletions
    if ($m == 0) {
        return map { ['delete', $_, undef] } (0 .. $n - 1);
    }

    # Build hash of base lines for quick lookup
    my %base_hash;
    for my $i (0 .. $n - 1) {
        push @{$base_hash{$base->[$i]}}, $i;
    }

    # Myers algorithm with linear space optimization
    my $max = $n + $m;
    my @v = (0) x (2 * $max + 1);
    my @trace;

    OUTER: for my $d (0 .. $max) {
        push @trace, [@v];  # Save state for backtracking

        for (my $k = -$d; $k <= $d; $k += 2) {
            my $idx = $k + $max;

            my $x;
            if ($k == -$d || ($k != $d && $v[$idx - 1] < $v[$idx + 1])) {
                $x = $v[$idx + 1];  # Move down
            } else {
                $x = $v[$idx - 1] + 1;  # Move right
            }

            my $y = $x - $k;

            # Follow diagonal (equal lines)
            while ($x < $n && $y < $m && $base->[$x] eq $current->[$y]) {
                $x++;
                $y++;
            }

            $v[$idx] = $x;

            if ($x >= $n && $y >= $m) {
                # Found the end, backtrack to build edit script
                return $class->_backtrack(\@trace, $base, $current, $n, $m, $max);
            }
        }
    }

    # Should never reach here
    return ();
}

# Backtrack through trace to build edit script
sub _backtrack {
    my ($class, $trace, $base, $current, $n, $m, $max) = @_;

    my @edits;
    my $x = $n;
    my $y = $m;

    for my $d (reverse 0 .. $#$trace) {
        my $v = $trace->[$d];
        my $k = $x - $y;
        my $idx = $k + $max;

        my $prev_k;
        if ($k == -$d || ($k != $d && $v->[$idx - 1] < $v->[$idx + 1])) {
            $prev_k = $k + 1;  # Came from above (insert)
        } else {
            $prev_k = $k - 1;  # Came from left (delete)
        }

        my $prev_idx = $prev_k + $max;
        my $prev_x = $v->[$prev_idx];
        my $prev_y = $prev_x - $prev_k;

        # Add diagonal moves (equal)
        while ($x > $prev_x && $y > $prev_y) {
            $x--;
            $y--;
            unshift @edits, ['equal', $x, $y];
        }

        if ($d > 0) {
            if ($x == $prev_x) {
                # Insert
                $y--;
                unshift @edits, ['insert', undef, $y];
            } else {
                # Delete
                $x--;
                unshift @edits, ['delete', $x, undef];
            }
        }
    }

    return @edits;
}

# =============================================================================
# Convert edit script to gutter indicators
# =============================================================================

# First, group consecutive non-equal edits into "hunks"
# Then classify each hunk:
#   - Only inserts → added lines
#   - Only deletes → deletion marker
#   - Both → modified lines (NO separate deletion marker)
#
# This ensures deletion markers never appear adjacent to added/modified lines.

sub _edits_to_indicators {
    my ($class, $edits, $base_lines, $current_lines) = @_;
    my $current_line_count = scalar(@$current_lines);

    # Step 1: Group edits into hunks
    # We need to track the current line number as we process edits
    my @hunks;
    my $current_hunk = undef;
    my $last_curr_line = -1;  # Track last seen current line number

    for my $i (0 .. $#$edits) {
        my $edit = $edits->[$i];
        my ($op, $base_line, $curr_line) = @$edit;

        if ($op eq 'equal') {
            # End current hunk if any
            if ($current_hunk) {
                # Find the next current line number to determine deletion position
                if (!defined $current_hunk->{next_curr_line}) {
                    $current_hunk->{next_curr_line} = $curr_line;
                }
                push @hunks, $current_hunk;
                $current_hunk = undef;
            }
            $last_curr_line = $curr_line;
        } else {
            # Start new hunk or continue existing one
            if (!$current_hunk) {
                $current_hunk = {
                    deletes => [],           # Base line numbers deleted
                    inserts => [],           # Current line numbers inserted
                    prev_curr_line => $last_curr_line,  # Line before this hunk
                    next_curr_line => undef,            # Line after this hunk (filled when hunk ends)
                };
            }

            if ($op eq 'delete') {
                push @{$current_hunk->{deletes}}, $base_line;
            } elsif ($op eq 'insert') {
                push @{$current_hunk->{inserts}}, $curr_line;
                $last_curr_line = $curr_line;
            }
        }
    }

    # Don't forget last hunk
    if ($current_hunk) {
        # No next line - hunk is at end of file
        $current_hunk->{next_curr_line} = undef;
        push @hunks, $current_hunk;
    }

    # Step 2: Classify hunks and convert to indicators
    my @added;
    my @modified;
    my @modified_whitespace;
    my @deleted;
    my @classified_hunks;

    for my $hunk (@hunks) {
        my $has_deletes = @{$hunk->{deletes}} > 0;
        my $has_inserts = @{$hunk->{inserts}} > 0;

        if ($has_deletes && $has_inserts) {
            # Both deletions and insertions = modified lines
            # Greedily pair each inserted line with the first available
            # whitespace-equivalent deleted line. Unpaired inserts are
            # content-modified (deletions absorbed).
            my @avail_deletes = @{$hunk->{deletes}};

            for my $ins_line (@{$hunk->{inserts}}) {
                my $ws_match_idx;
                for my $j (0 .. $#avail_deletes) {
                    if ($class->_is_whitespace_only_line_change(
                            $base_lines->[$avail_deletes[$j]],
                            $current_lines->[$ins_line])) {
                        $ws_match_idx = $j;
                        last;
                    }
                }

                if (defined $ws_match_idx) {
                    push @modified_whitespace, $ins_line;
                    splice(@avail_deletes, $ws_match_idx, 1);
                } else {
                    push @modified, $ins_line;
                }
            }

            push @classified_hunks, {
                type           => 'modified',
                base_lines     => $hunk->{deletes},
                current_lines  => $hunk->{inserts},
                prev_curr_line => $hunk->{prev_curr_line},
                next_curr_line => $hunk->{next_curr_line},
            };
        }
        elsif ($has_inserts) {
            # Only insertions = added lines
            push @added, @{$hunk->{inserts}};

            push @classified_hunks, {
                type           => 'added',
                base_lines     => [],
                current_lines  => $hunk->{inserts},
                prev_curr_line => $hunk->{prev_curr_line},
                next_curr_line => $hunk->{next_curr_line},
            };
        }
        elsif ($has_deletes) {
            # Only deletions = deletion marker
            my $marker_line;
            if ($hunk->{prev_curr_line} == -1) {
                $marker_line = 0;
            } elsif (!defined $hunk->{next_curr_line}) {
                $marker_line = $current_line_count > 0 ? $current_line_count - 1 : 0;
            } else {
                $marker_line = $hunk->{prev_curr_line};
            }

            if (!@deleted || $deleted[-1] != $marker_line) {
                push @deleted, $marker_line;
            }

            push @classified_hunks, {
                type           => 'deleted',
                base_lines     => $hunk->{deletes},
                current_lines  => [],
                prev_curr_line => $hunk->{prev_curr_line},
                next_curr_line => $hunk->{next_curr_line},
            };
        }
    }

    return {
        added               => \@added,
        modified            => \@modified,
        modified_whitespace => \@modified_whitespace,
        deleted             => \@deleted,
        hunks               => \@classified_hunks,
    };
}

# Check if a single line pair differs only in whitespace
sub _is_whitespace_only_line_change {
    my ($class, $base_line, $curr_line) = @_;

    # Strip all whitespace and compare
    (my $base_stripped = $base_line) =~ s/\s+//g;
    (my $curr_stripped = $curr_line) =~ s/\s+//g;

    return $base_stripped eq $curr_stripped;
}

1;
