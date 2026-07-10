#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;

use lib 'lib';
use Zepto::WrapMap;
use Zepto::Renderer;
use Zepto::Document;

# Helper: create a document with given lines
sub make_doc {
    my @lines = @_;
    my $content = join("\n", @lines) . "\n";
    my $doc = Zepto::Document->new();
    # Replace buffer content
    my $buf = $doc->{buffer};
    $buf->{pre_gap} = $content;
    $buf->{post_gap} = '';
    $buf->{_line_index} = undef;  # Force rebuild
    return $doc;
}

# Helper: create WrapMap for lines at given width
sub make_wm {
    my ($width, @lines) = @_;
    my $doc = make_doc(@lines);
    my $wm = Zepto::WrapMap->new(
        document => $doc,
        width    => $width,
    );
    return ($wm, $doc);
}

# =============================================================================
# Basic wrapping tests
# =============================================================================

subtest 'Short line - no wrap' => sub {
    my ($wm) = make_wm(80, "Hello world");
    my $segs = $wm->segments_for_line(0);
    is(scalar @$segs, 1, 'Single segment');
    is($segs->[0]{wrap_index}, 0, 'wrap_index is 0');
    is($segs->[0]{col_start}, 0, 'col_start is 0');
    is($segs->[0]{col_end}, 11, 'col_end is line length');
    is($segs->[0]{vis_start}, 0, 'vis_start is 0');
    is($segs->[0]{vis_end}, 11, 'vis_end is line length');
    is($segs->[0]{indent_width}, 0, 'no indent');
};

subtest 'Line exactly at width boundary - no wrap' => sub {
    my $line = 'x' x 40;
    my ($wm) = make_wm(40, $line);
    my $segs = $wm->segments_for_line(0);
    is(scalar @$segs, 1, 'Single segment for exact-width line');
};

subtest 'Empty line - no wrap' => sub {
    my ($wm) = make_wm(80, "");
    my $segs = $wm->segments_for_line(0);
    is(scalar @$segs, 1, 'Single segment for empty line');
    is($segs->[0]{col_start}, 0);
    is($segs->[0]{col_end}, 0);
    is($segs->[0]{vis_start}, 0);
    is($segs->[0]{vis_end}, 0);
};

subtest 'Long line wraps at word boundary' => sub {
    # 20-char width, line with spaces for word breaks
    my $line = "hello world this is a long line that wraps";
    my ($wm) = make_wm(20, $line);
    my $segs = $wm->segments_for_line(0);
    ok(scalar @$segs > 1, 'Multiple segments for long line');

    # First segment should break at a word boundary (space)
    my $first = $segs->[0];
    is($first->{wrap_index}, 0, 'First segment wrap_index 0');
    is($first->{indent_width}, 0, 'First segment has no indent');
    # Check that it broke at a space
    my $first_text = substr($line, $first->{col_start}, $first->{col_end} - $first->{col_start});
    ok(length($first_text) <= 20, 'First segment fits in width');

    # Second segment should be a continuation
    my $second = $segs->[1];
    is($second->{wrap_index}, 1, 'Second segment is continuation');
    is($second->{col_start}, $first->{col_end}, 'Second starts where first ended');

    # Verify coverage: all segments cover the entire line
    my $total_chars = 0;
    for my $seg (@$segs) {
        $total_chars += $seg->{col_end} - $seg->{col_start};
    }
    is($total_chars, length($line), 'Segments cover entire line');
};

subtest 'Long line without spaces - hard break' => sub {
    my $line = 'x' x 50;
    my ($wm) = make_wm(20, $line);
    my $segs = $wm->segments_for_line(0);
    is(scalar @$segs, 3, '50 chars / 20 width = 3 segments');

    # First segment: chars 0..19 (20 chars)
    is($segs->[0]{col_start}, 0);
    is($segs->[0]{col_end}, 20);

    # Second segment: chars 20..39 (20 chars)
    is($segs->[1]{col_start}, 20);
    is($segs->[1]{col_end}, 40);

    # Third segment: chars 40..49 (10 chars)
    is($segs->[2]{col_start}, 40);
    is($segs->[2]{col_end}, 50);
};

subtest 'Hanging indent on continuation rows' => sub {
    # Indented line that wraps
    my $line = "    " . ("word " x 20);  # 4 spaces indent + long text
    $line =~ s/\s+$//;  # trim trailing space
    my ($wm) = make_wm(30, $line);
    my $segs = $wm->segments_for_line(0);
    ok(scalar @$segs > 1, 'Line wraps');

    is($segs->[0]{indent_width}, 0, 'First row has no hanging indent');
    is($segs->[1]{indent_width}, 4, 'Continuation row inherits 4-space indent');

    # Verify continuation row has less effective width
    my $first_vis_len = $segs->[0]{vis_end} - $segs->[0]{vis_start};
    my $second_vis_len = $segs->[1]{vis_end} - $segs->[1]{vis_start};
    ok($first_vis_len > $second_vis_len || $first_vis_len == 30,
       'Continuation has reduced effective width due to indent');
};

subtest 'Indent clamping when indent is too large' => sub {
    # 20-width viewport, 18-space indent — leaves only 2 chars, below MIN_CONTENT_COLS
    my $line = (' ' x 18) . "abc def ghi jkl mno pqr stu vwx";
    my ($wm) = make_wm(20, $line);
    my $segs = $wm->segments_for_line(0);
    ok(scalar @$segs > 1, 'Line wraps');

    # indent_width should be clamped to 0 since 18 > 20 - 4
    is($segs->[1]{indent_width}, 0, 'Indent clamped to 0 when too large');
};

# =============================================================================
# Tab handling
# =============================================================================

subtest 'Tab expansion in wrapping' => sub {
    # Tab at position 0 expands to 4 spaces, so visual width = 4 + rest
    my $line = "\t" . ("abcdef " x 15);  # tab + long text
    $line =~ s/\s+$//;
    my ($wm) = make_wm(20, $line);
    my $segs = $wm->segments_for_line(0);
    ok(scalar @$segs > 1, 'Tab-containing line wraps');

    # First segment's visual width should include tab expansion
    my $vis_width = $segs->[0]{vis_end} - $segs->[0]{vis_start};
    ok($vis_width <= 20, 'First segment visual width fits in viewport');
};

# =============================================================================
# Visual row mapping
# =============================================================================

subtest 'doc_line_to_visual_row' => sub {
    my ($wm) = make_wm(10, "short", "this is a longer line that wraps", "end");
    # Line 0: "short" (5 chars) — 1 row
    # Line 1: long line — multiple rows
    # Line 2: "end" — 1 row

    is($wm->doc_line_to_visual_row(0), 0, 'Line 0 starts at visual row 0');
    is($wm->doc_line_to_visual_row(1), 1, 'Line 1 starts at visual row 1');

    my $line1_rows = $wm->visual_rows_for_line(1);
    ok($line1_rows > 1, 'Line 1 occupies multiple visual rows');

    is($wm->doc_line_to_visual_row(2), 1 + $line1_rows, 'Line 2 starts after line 1');
};

subtest 'segment_at_visual_row' => sub {
    my ($wm) = make_wm(10, "short", "this is a longer line");

    my $seg0 = $wm->segment_at_visual_row(0);
    is($seg0->{doc_line}, 0, 'Visual row 0 = doc line 0');
    is($seg0->{wrap_index}, 0);

    my $seg1 = $wm->segment_at_visual_row(1);
    is($seg1->{doc_line}, 1, 'Visual row 1 = doc line 1 (first row)');
    is($seg1->{wrap_index}, 0);

    my $seg2 = $wm->segment_at_visual_row(2);
    is($seg2->{doc_line}, 1, 'Visual row 2 = doc line 1 (continuation)');
    is($seg2->{wrap_index}, 1);
};

subtest 'total_visual_rows' => sub {
    my ($wm) = make_wm(10, "short", "x" x 25);
    # "short" = 1 row, "xxx...25" = 3 rows (10+10+5), + trailing empty line = 1 row
    is($wm->total_visual_rows(), 5, 'Total visual rows = 1 + 3 + 1 (trailing newline)');
};

# =============================================================================
# Coordinate conversion
# =============================================================================

subtest 'doc_to_visual basic' => sub {
    my ($wm) = make_wm(10, "hello world testing");
    # "hello world testing" = 19 chars, wraps at ~10
    # Assuming "hello " breaks... let's check
    my $segs = $wm->segments_for_line(0);
    my $seg0_end = $segs->[0]{col_end};

    # Cursor at position 0 should be on visual row 0
    my ($vrow, $vcol) = $wm->doc_to_visual(0, 0);
    is($vrow, 0, 'doc col 0 on visual row 0');
    is($vcol, 0, 'doc col 0 at visual col 0');

    # Cursor at position beyond first segment should be on next visual row
    if (@$segs > 1) {
        my ($vrow2, $vcol2) = $wm->doc_to_visual(0, $seg0_end);
        is($vrow2, 1, 'cursor at segment boundary on next visual row');
    }
};

subtest 'doc_to_visual / visual_to_doc round-trip' => sub {
    my ($wm) = make_wm(15, "The quick brown fox jumps over the lazy dog");

    # Test various positions in the line
    for my $col (0, 5, 10, 15, 20, 25, 30, 35, 40, 43) {
        my ($vrow, $vcol) = $wm->doc_to_visual(0, $col);
        my ($doc_line, $doc_col) = $wm->visual_to_doc($vrow, $vcol);
        is($doc_line, 0, "Round-trip line for col $col");
        is($doc_col, $col, "Round-trip col for col $col");
    }
};

subtest 'visual_to_doc clamps to segment' => sub {
    my ($wm) = make_wm(10, "short", "x" x 25);

    # Click at a very large column on a short line
    my ($line, $col) = $wm->visual_to_doc(0, 100);
    is($line, 0, 'Clamped to line 0');
    is($col, 5, 'Clamped to line length');
};

subtest 'doc_to_visual with multiple lines' => sub {
    my ($wm) = make_wm(10, "short", "x" x 25, "end");
    # Line 0: 1 visual row
    # Line 1: 3 visual rows (25/10)
    # Line 2: 1 visual row, starts at vrow 4

    my ($vrow, $vcol) = $wm->doc_to_visual(2, 0);
    is($vrow, 4, 'Line 2 at visual row 4');
    is($vcol, 0, 'Column 0');
};

subtest 'visual_to_doc beyond document' => sub {
    my ($wm, $doc) = make_wm(80, "only line");
    # Total is 2 visual rows (line 0 + trailing empty line 1), so row 5 is beyond
    my ($line, $col) = $wm->visual_to_doc(5, 0);
    is($line, 1, 'Clamped to last line (trailing empty)');
};

subtest 'visual_to_doc negative vrow clamps to document start' => sub {
    my ($wm, $doc) = make_wm(10, "short", "x" x 25, "end");
    # Dragging the mouse above the text viewport in wrap mode can produce a
    # negative visual row. This must clamp to line 0, col 0 — not jump to
    # the end of the document (regression for bugs.md P1 mouse drag bug).
    my ($line, $col) = $wm->visual_to_doc(-1, 0);
    is($line, 0, 'Negative vrow clamps to line 0');
    is($col, 0, 'Negative vrow clamps to col 0');

    ($line, $col) = $wm->visual_to_doc(-100, 50);
    is($line, 0, 'Large negative vrow still clamps to line 0');
    is($col, 0, 'Large negative vrow still clamps to col 0');
};

# =============================================================================
# Invalidation
# =============================================================================

subtest 'invalidate forces rebuild' => sub {
    my ($wm) = make_wm(80, "hello");
    # 2 rows: "hello" + trailing empty line
    is($wm->total_visual_rows(), 2, 'Initially 2 rows (line + trailing newline)');

    $wm->invalidate();
    ok($wm->{_dirty}, 'Marked dirty after invalidate');

    # Access triggers rebuild
    is($wm->total_visual_rows(), 2, 'Rebuilt on access');
    ok(!$wm->{_dirty}, 'No longer dirty after rebuild');
};

# =============================================================================
# Hanging indent with doc_to_visual
# =============================================================================

subtest 'doc_to_visual accounts for indent_width' => sub {
    # 4 spaces indent, line wraps at width 15
    my $line = "    " . "word " x 10;
    $line =~ s/\s+$//;
    my ($wm) = make_wm(15, $line);

    my $segs = $wm->segments_for_line(0);
    if (@$segs > 1 && $segs->[1]{indent_width} > 0) {
        # Cursor on first char of second segment
        my $col = $segs->[1]{col_start};
        my ($vrow, $vcol) = $wm->doc_to_visual(0, $col);
        is($vrow, 1, 'On second visual row');
        # vcol should be indent_width (since content starts after indent)
        is($vcol, $segs->[1]{indent_width}, 'Visual col accounts for indent');
    }
};

# =============================================================================
# Incremental invalidation (invalidate_line)
# =============================================================================

subtest 'invalidate_line updates single line without full rebuild' => sub {
    my ($wm, $doc) = make_wm(10, "short", "x" x 25, "end");
    # Force initial build: "short"(1) + "xxx..."(3) + "end"(1) + trailing ""(1) = 6
    is($wm->total_visual_rows(), 6, 'Initial: 1 + 3 + 1 + 1 (trailing) = 6 visual rows');
    my $old_vrow_line2 = $wm->doc_line_to_visual_row(2);
    is($old_vrow_line2, 4, 'Line 2 starts at vrow 4');

    # Modify line 0 via document (add chars to make it wrap)
    my $offset = $doc->line_col_to_offset(0, 5);  # end of "short"
    $doc->insert($offset, " plus extra text");  # "short plus extra text" — wraps at width 10

    # Call incremental invalidate for line 0
    $wm->invalidate_line(0);

    # Line 0 should now have multiple segments
    my $segs0 = $wm->segments_for_line(0);
    ok(scalar @$segs0 > 1, 'Line 0 now wraps after incremental update');

    # Total visual rows should have increased from the initial 6
    my $new_total = $wm->total_visual_rows();
    ok($new_total > 6, "Total visual rows increased (got $new_total)");

    # Line 1 segments should be unchanged (still 3 visual rows for "x" x 25)
    my $segs1 = $wm->segments_for_line(1);
    is(scalar @$segs1, 3, 'Line 1 still has 3 segments');

    # Line 2's visual row offset should have shifted by delta
    my $delta = scalar @$segs0 - 1;  # was 1 segment, now more
    is($wm->doc_line_to_visual_row(2), $old_vrow_line2 + $delta,
       'Line 2 vrow shifted by delta');

    # Verify segments are consistent with _visual_rows
    my $seg_at_0 = $wm->segment_at_visual_row(0);
    is($seg_at_0->{doc_line}, 0, 'Visual row 0 is still line 0');

    # Verify _ensure_built doesn't trigger full rebuild (version synced)
    ok(!$wm->{_dirty}, 'Not dirty after invalidate_line');
    is($wm->{_last_content_version}, $doc->content_version(),
       'Version synced — no full rebuild needed');
};

subtest 'invalidate_line with no segment count change' => sub {
    # Line that wraps into exactly 2 segments; modify content but keep same wrap
    my ($wm, $doc) = make_wm(10, "abcdefghijklmno");  # 15 chars → 2 segments
    is($wm->total_visual_rows(), 3, '2 segments for line 0 + 1 trailing = 3');
    my $old_total = $wm->total_visual_rows();

    # Replace a character within line 0 (no length change)
    my $offset = $doc->line_col_to_offset(0, 0);
    $doc->delete($offset, 1);
    $doc->insert($offset, 'X');

    # Two version bumps — invalidate_line should fall back to dirty
    # Actually this is 2 increments, so version drift > 1 → falls back to full rebuild
    $wm->invalidate_line(0);
    # Since drift > 1, it sets _dirty. Next query does full rebuild.
    is($wm->total_visual_rows(), 3, 'Total rows unchanged after single-char replace');
};

subtest 'invalidate_line on unbuilt map is a no-op' => sub {
    my $doc = make_doc("hello", "world");
    my $wm = Zepto::WrapMap->new(document => $doc, width => 80);
    # Don't query — map is still unbuilt (_dirty=1)
    ok($wm->{_dirty}, 'Map is dirty initially');

    $wm->invalidate_line(0);  # Should be a no-op since map is dirty
    ok($wm->{_dirty}, 'Still dirty — invalidate_line was a no-op');
};

subtest 'invalidate_line shrinks segment count' => sub {
    # Start with a wrapping line, then shorten it to fit in one segment
    my ($wm, $doc) = make_wm(10, "abcdefghijklmno", "tail");
    # Line 0: 15 chars → 2 segments. Line 1: 4 chars → 1 segment.
    is($wm->total_visual_rows(), 4, 'Initial: 2 + 1 + 1 (trailing) = 4');
    is($wm->doc_line_to_visual_row(1), 2, 'Line 1 at vrow 2');

    # Delete chars from line 0 to make it fit in 1 segment
    $doc->delete($doc->line_col_to_offset(0, 5), 10);  # "abcde" remains

    $wm->invalidate_line(0);

    is(scalar @{$wm->segments_for_line(0)}, 1, 'Line 0 now 1 segment');
    is($wm->total_visual_rows(), 3, 'Total: 1 + 1 + 1 = 3');
    is($wm->doc_line_to_visual_row(1), 1, 'Line 1 shifted up to vrow 1');
};

subtest 'doc_to_visual correct after invalidate_line' => sub {
    my ($wm, $doc) = make_wm(20, "hello world", "second line here");
    # Both lines fit in width 20 — 1 segment each + trailing
    is($wm->total_visual_rows(), 3, 'Initial: 3 visual rows');

    # Make line 0 longer so it wraps
    $doc->insert($doc->line_col_to_offset(0, 11), " and more text added");
    $wm->invalidate_line(0);

    # Verify doc_to_visual still works correctly for line 1
    my ($vrow1, $vcol1) = $wm->doc_to_visual(1, 0);
    is($vrow1, $wm->doc_line_to_visual_row(1), 'doc_to_visual consistent with doc_line_to_visual_row');
    ok($vrow1 > 1, 'Line 1 visual row shifted down due to line 0 wrapping');
};

done_testing();
