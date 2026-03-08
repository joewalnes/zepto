package Zepto::Minimap;
# =============================================================================
# Minimap: Pure computation module for minimap/scrollbar data
# =============================================================================
#
# Computes minimap data from document state. No rendering or ANSI codes —
# just data structures that Renderer can use.
#
# The minimap maps the entire document onto a fixed number of display rows,
# showing text density via braille characters, VCS change indicators, and
# the current viewport position.
#
# Row data (braille + VCS) is cached and only recomputed when the document
# changes. Viewport/cursor positions are always recomputed (cheap arithmetic).
# =============================================================================

use strict;
use warnings;
use utf8;

use POSIX qw(ceil floor);

# Minimap layout constants
use constant {
    MINIMAP_TOTAL_WIDTH  => 8,   # Total minimap column width (separator + vcs + text)
    MINIMAP_SEPARATOR    => 1,   # Thin separator column between text and minimap
    MINIMAP_VCS_COL      => 1,   # Column for VCS change indicators
    MINIMAP_TEXT_COLS     => 6,   # Columns for braille text density
};

# Braille character base (U+2800)
use constant BRAILLE_BASE => 0x2800;

# Maximum number of lines to sample per minimap row for braille computation.
# When lines_per_row > this, we subsample instead of reading every line.
use constant MAX_SAMPLE_LINES => 4;

# 8-dot braille dot layout:
#   Col0  Col1
#   d1    d4     row 0  (bits 0, 3)
#   d2    d5     row 1  (bits 1, 4)
#   d3    d6     row 2  (bits 2, 5)
#   d7    d8     row 3  (bits 6, 7)
my @BRAILLE_BITS = (
    [0, 3],  # row 0
    [1, 4],  # row 1
    [2, 5],  # row 2
    [6, 7],  # row 3
);

# Module-level cache for row data (braille + VCS)
my %_cache;  # doc_id => { key => ..., rows => [...], lines_per_row => ..., total_rows => ... }

# =============================================================================
# Public API
# =============================================================================

# Compute minimap data for the entire document.
#
# Args (named):
#   document       - Zepto::Document instance
#   view           - Zepto::View instance
#   height         - Number of minimap rows available (text area height)
#
# Returns hashref:
#   rows           - Arrayref of row data: [{ braille => "⣿⡇...", vcs => status }, ...]
#   viewport_start - First minimap row in the visible viewport
#   viewport_end   - Last minimap row in the visible viewport
#   cursor_row     - Minimap row containing the cursor line
#   lines_per_row  - Float: how many doc lines each minimap row represents
#   total_rows     - Number of minimap rows actually used (may be < height)
sub compute {
    my ($class, %args) = @_;

    my $doc    = $args{document};
    my $view   = $args{view};
    my $height = $args{height};

    my $total_lines = $doc ? $doc->line_count() : 0;

    # Empty document
    if ($total_lines == 0 || $height == 0) {
        return {
            rows           => [],
            viewport_start => 0,
            viewport_end   => 0,
            cursor_row     => 0,
            lines_per_row  => 1,
            total_rows     => 0,
        };
    }

    # Get cached row data or recompute
    my $row_data = $class->_get_cached_rows($doc, $height, $total_lines);

    # Viewport position (cheap — always recompute)
    my $lines_per_row = $row_data->{lines_per_row};
    my $used_rows = $row_data->{total_rows};

    my $scroll_line = $view ? $view->scroll_line() : 0;
    my $viewport_rows = $view ? $view->viewport_rows() : $height;
    my $cursor_line = $view ? $view->cursor_line() : 0;

    my $viewport_start = floor($scroll_line / $lines_per_row);
    my $viewport_end = floor(($scroll_line + $viewport_rows - 1) / $lines_per_row);
    $viewport_start = 0 if $viewport_start < 0;
    $viewport_end = $used_rows - 1 if $viewport_end >= $used_rows;

    my $cursor_row = floor($cursor_line / $lines_per_row);
    $cursor_row = $used_rows - 1 if $cursor_row >= $used_rows;
    $cursor_row = 0 if $cursor_row < 0;

    return {
        rows           => $row_data->{rows},
        viewport_start => $viewport_start,
        viewport_end   => $viewport_end,
        cursor_row     => $cursor_row,
        lines_per_row  => $lines_per_row,
        total_rows     => $used_rows,
    };
}

# Convert a minimap row click to the document line it represents.
sub row_to_doc_line {
    my ($class, $minimap_row, $lines_per_row) = @_;
    return int($minimap_row * $lines_per_row);
}

# Clear the cache (for testing or when document is replaced)
sub invalidate_cache {
    %_cache = ();
}

# =============================================================================
# Caching
# =============================================================================

# Build a cache key from document state.
# Changes when: content is edited (undo/redo stack sizes change),
# line count changes, or minimap height changes.
sub _cache_key {
    my ($doc, $height, $total_lines) = @_;
    # Use content_version (incremented on every edit) to detect content changes.
    # Previous approach used undo/redo stack sizes which also change every keystroke
    # but caused unnecessary cache misses since undo_size != content identity.
    my $content_ver = $doc->content_version();
    # VCS diff timestamp only changes when the debounced diff runs (~0.3-1s),
    # preventing needless cache misses during rapid typing.
    my $vcs_diff_ver = int(($doc->{_vcs_last_diff} // 0) * 1000);
    return "$total_lines:$height:$content_ver:$vcs_diff_ver";
}

sub _get_cached_rows {
    my ($class, $doc, $height, $total_lines) = @_;

    my $doc_id = "$doc";  # Stringified reference as identity
    my $key = _cache_key($doc, $height, $total_lines);

    if ($_cache{$doc_id} && $_cache{$doc_id}{key} eq $key) {
        return $_cache{$doc_id};
    }

    # Recompute row data
    my $lines_per_row = $total_lines / $height;
    $lines_per_row = 1 if $lines_per_row < 1;
    my $used_rows = $total_lines <= $height ? $total_lines : $height;

    my @rows;
    for my $row (0 .. $used_rows - 1) {
        my $start_line = int($row * $lines_per_row);
        my $end_line = int(($row + 1) * $lines_per_row);
        $end_line = $total_lines if $end_line > $total_lines;
        $end_line = $start_line + 1 if $end_line <= $start_line;
        $end_line = $total_lines if $end_line > $total_lines;

        my $line_span = $end_line - $start_line;

        # Sample lines for braille — only read up to MAX_SAMPLE_LINES
        my @sample_lines;
        if ($line_span <= MAX_SAMPLE_LINES) {
            for my $l ($start_line .. $end_line - 1) {
                push @sample_lines, $doc->get_line_content($l) // '';
            }
        } else {
            # Subsample: pick 4 evenly-spaced lines
            for my $i (0 .. MAX_SAMPLE_LINES - 1) {
                my $l = $start_line + int($i * ($line_span - 1) / (MAX_SAMPLE_LINES - 1));
                push @sample_lines, $doc->get_line_content($l) // '';
            }
        }

        my $braille = _compute_braille(\@sample_lines, MINIMAP_TEXT_COLS);
        my $vcs = _aggregate_vcs_status($doc, $start_line, $end_line);

        push @rows, {
            braille => $braille,
            vcs     => $vcs,
        };
    }

    # Store in cache
    my $result = {
        key           => $key,
        rows          => \@rows,
        lines_per_row => $lines_per_row,
        total_rows    => $used_rows,
    };
    # Only cache one doc at a time (single-document editor)
    %_cache = ($doc_id => $result);

    return $result;
}

# =============================================================================
# Private helpers
# =============================================================================

# Compute braille text density string for a group of document lines.
#
# Each braille character is a 2×4 dot grid. Horizontally, each dot covers
# a range of source characters (not just a single point). A dot lights up
# if ANY non-whitespace character exists in that range, giving an accurate
# silhouette of the code's indentation and density structure.
#
# Vertically, each dot row maps to one sampled line. If fewer than 4 lines
# are available, unused rows remain blank (no dots) instead of repeating.
sub _compute_braille {
    my ($lines_ref, $text_cols) = @_;

    return chr(BRAILLE_BASE) x $text_cols unless @$lines_ref;

    # Find maximum line length for horizontal scaling
    my $max_len = 0;
    for my $line (@$lines_ref) {
        my $len = length($line);
        $max_len = $len if $len > $max_len;
    }

    return chr(BRAILLE_BASE) x $text_cols if $max_len == 0;

    # Each braille char is 2 dots wide; total horizontal dots = text_cols * 2
    my $dot_cols = $text_cols * 2;
    my $chars_per_dot = $max_len / $dot_cols;
    $chars_per_dot = 1 if $chars_per_dot < 1;

    my $num_lines = scalar @$lines_ref;

    my $result = '';
    for my $col (0 .. $text_cols - 1) {
        my $bits = 0;

        for my $row (0 .. 3) {
            # Map braille row to a sampled line; skip if no line for this row
            my $line_idx;
            if ($num_lines <= 4) {
                next if $row >= $num_lines;  # Leave unused rows blank
                $line_idx = $row;
            } else {
                $line_idx = int($row * ($num_lines - 1) / 3);
            }
            my $line = $lines_ref->[$line_idx];
            my $line_len = length($line);

            # Left dot — check if any non-whitespace in the covered range
            my $left_start = int($col * 2 * $chars_per_dot);
            my $left_end   = int(($col * 2 + 1) * $chars_per_dot);
            $left_end = $line_len if $left_end > $line_len;
            if ($left_start < $line_len) {
                my $seg_len = $left_end - $left_start;
                if ($seg_len > 0) {
                    my $seg = substr($line, $left_start, $seg_len);
                    # Fast scan: any character that isn't space or tab
                    for my $i (0 .. $seg_len - 1) {
                        my $ch = substr($seg, $i, 1);
                        if ($ch ne ' ' && $ch ne "\t") {
                            $bits |= (1 << $BRAILLE_BITS[$row][0]);
                            last;
                        }
                    }
                }
            }

            # Right dot — same range check
            my $right_start = int(($col * 2 + 1) * $chars_per_dot);
            my $right_end   = int(($col * 2 + 2) * $chars_per_dot);
            $right_end = $line_len if $right_end > $line_len;
            if ($right_start < $line_len) {
                my $seg_len = $right_end - $right_start;
                if ($seg_len > 0) {
                    my $seg = substr($line, $right_start, $seg_len);
                    for my $i (0 .. $seg_len - 1) {
                        my $ch = substr($seg, $i, 1);
                        if ($ch ne ' ' && $ch ne "\t") {
                            $bits |= (1 << $BRAILLE_BITS[$row][1]);
                            last;
                        }
                    }
                }
            }
        }

        $result .= chr(BRAILLE_BASE + $bits);
    }

    return $result;
}

# Aggregate VCS change status for a range of document lines.
# Priority: deleted > modified > added.
sub _aggregate_vcs_status {
    my ($doc, $start_line, $end_line) = @_;

    return undef unless $doc && $doc->can('vcs_change_status');

    my $has_added = 0;
    my $has_modified = 0;
    my $has_deleted = 0;

    my $line_count = $doc->line_count();

    for my $line ($start_line .. $end_line - 1) {
        last if $line >= $line_count;

        my $change = $doc->vcs_change_status($line);
        if ($change) {
            if ($change eq 'added') {
                $has_added = 1;
            } else {
                $has_modified = 1;
            }
        }

        my $del = $doc->vcs_deletion_status($line);
        $has_deleted = 1 if $del;

        # Short-circuit: once we've found deleted (highest priority), no need to continue
        last if $has_deleted;
    }

    return 'deleted'  if $has_deleted;
    return 'modified' if $has_modified;
    return 'added'    if $has_added;
    return undef;
}

1;
