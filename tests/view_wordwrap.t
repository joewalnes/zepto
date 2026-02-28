#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;

use lib 'lib';
use Zepto::View;
use Zepto::WrapMap;
use Zepto::Document;

# Helper: create a document with given lines
sub make_doc {
    my @lines = @_;
    my $content = join("\n", @lines) . "\n";
    my $doc = Zepto::Document->new();
    my $buf = $doc->{buffer};
    $buf->{pre_gap} = $content;
    $buf->{post_gap} = '';
    $buf->{_line_index} = undef;
    return $doc;
}

# Helper: create View + WrapMap for lines at given width
sub make_view {
    my ($width, @lines) = @_;
    my $doc = make_doc(@lines);
    my $view = Zepto::View->new(
        document      => $doc,
        viewport_rows => 20,
        viewport_cols => $width + 10,  # Some extra for gutter etc.
    );
    my $wm = Zepto::WrapMap->new(
        document => $doc,
        width    => $width,
    );
    $view->set_wrap_map($wm);
    return ($view, $doc, $wm);
}

# =============================================================================
# Cursor movement across wrap boundaries
# =============================================================================

subtest 'move_down through wrapped line' => sub {
    # Line 0: "short" (1 visual row)
    # Line 1: 25 x's (3 visual rows at width 10)
    # Line 2: "end" (1 visual row)
    my ($view, $doc, $wm) = make_view(10, "short", "x" x 25, "end");

    # Start at line 0, col 0
    $view->set_cursor(0, 0);
    is($view->cursor_line(), 0, 'Start at line 0');
    is($view->cursor_col(), 0, 'Start at col 0');

    # Move down: should go to first visual row of line 1
    $view->move_down();
    is($view->cursor_line(), 1, 'Down to line 1');
    is($view->cursor_col(), 0, 'At col 0 of line 1');

    # Move down again: should go to second visual row of line 1 (col ~10)
    $view->move_down();
    is($view->cursor_line(), 1, 'Still on line 1');
    is($view->cursor_col(), 10, 'At col 10 (second wrap row)');

    # Move down again: third visual row of line 1
    $view->move_down();
    is($view->cursor_line(), 1, 'Still on line 1');
    is($view->cursor_col(), 20, 'At col 20 (third wrap row)');

    # Move down again: should go to line 2
    $view->move_down();
    is($view->cursor_line(), 2, 'Down to line 2');
    is($view->cursor_col(), 0, 'At col 0 of line 2');
};

subtest 'move_up through wrapped line' => sub {
    my ($view, $doc, $wm) = make_view(10, "short", "x" x 25, "end");

    # Start at line 2, col 0
    $view->set_cursor(2, 0);

    # Move up: should go to last visual row of line 1
    $view->move_up();
    is($view->cursor_line(), 1, 'Up to line 1');
    is($view->cursor_col(), 20, 'At col 20 (last wrap row of line 1)');

    # Move up: second visual row of line 1
    $view->move_up();
    is($view->cursor_line(), 1, 'Still on line 1');
    is($view->cursor_col(), 10, 'At col 10');

    # Move up: first visual row of line 1
    $view->move_up();
    is($view->cursor_line(), 1, 'Still on line 1');
    is($view->cursor_col(), 0, 'At col 0');

    # Move up: line 0
    $view->move_up();
    is($view->cursor_line(), 0, 'Up to line 0');
};

subtest 'preferred_col preserved across wrap rows' => sub {
    # Use a wider width with word wrap
    my ($view, $doc, $wm) = make_view(10, "x" x 25, "y" x 25);

    # Start at line 0, col 5 (middle of first wrap row)
    $view->set_cursor(0, 5);

    # Move down: should stay at col ~5 in second wrap row
    $view->move_down();
    is($view->cursor_line(), 0, 'Still on line 0');
    is($view->cursor_col(), 15, 'Preferred col 5 maps to col 15 in second wrap row');

    # Move down: third wrap row, still col ~5
    $view->move_down();
    is($view->cursor_line(), 0, 'Still on line 0');
    is($view->cursor_col(), 25, 'Preferred col 5 maps to col 25 (clamped to line end)');
};

# =============================================================================
# Line start/end with word wrap
# =============================================================================

subtest 'move_to_line_start on continuation row' => sub {
    my ($view, $doc, $wm) = make_view(10, "x" x 25);

    # Move to second wrap row
    $view->set_cursor(0, 15);
    my ($vrow, $vcol) = $wm->doc_to_visual(0, 15);

    $view->move_to_line_start();
    is($view->cursor_col(), 10, 'Home goes to start of current wrap row');
};

subtest 'move_to_line_end on non-final wrap row' => sub {
    my ($view, $doc, $wm) = make_view(10, "x" x 25);

    # Move to first wrap row (not the last segment)
    $view->set_cursor(0, 5);

    $view->move_to_line_end();
    # END goes to col_end of current segment; 'left' affinity keeps cursor on this row
    my $segs = $wm->segments_for_line(0);
    my $expected_end = $segs->[0]{col_end};
    is($view->cursor_col(), $expected_end, 'End goes to col_end of current wrap row');

    # Verify cursor affinity is 'left' so it renders on the correct visual row
    is($view->cursor_affinity(), 'left', 'END sets left affinity for segment boundary');

    # Verify doc_to_visual with left affinity maps to the current visual row, not the next
    my ($vrow_left, $vcol_left) = $wm->doc_to_visual(0, $expected_end, 'left');
    my ($vrow_right, $vcol_right) = $wm->doc_to_visual(0, $expected_end, 'right');
    is($vrow_left, 0, 'Left affinity: cursor at col_end stays on visual row 0');
    is($vrow_right, 1, 'Right affinity: cursor at col_end maps to visual row 1');
};

subtest 'move_to_line_end on final wrap row' => sub {
    my ($view, $doc, $wm) = make_view(10, "x" x 25);

    # Move to last wrap row (segment 2: chars 20-24)
    $view->set_cursor(0, 22);

    $view->move_to_line_end();
    # For the final segment, END goes to line length (standard behavior)
    my $line_len = $doc->line_length(0);
    is($view->cursor_col(), $line_len, 'End goes to line length on final wrap row');
};

# =============================================================================
# ensure_cursor_visible with word wrap
# =============================================================================

subtest 'ensure_cursor_visible scrolls for wrapped content' => sub {
    my ($view, $doc, $wm) = make_view(10,
        "short",                    # line 0: 1 vrow
        "x" x 100,                  # line 1: 10 vrows
        "end",                      # line 2: 1 vrow
    );
    $view->{viewport_rows} = 5;

    # Place cursor on line 2 (which starts at visual row 11)
    $view->set_cursor(2, 0);
    $view->ensure_cursor_visible();

    # scroll_line should have advanced so line 2 is visible
    my $scroll_vrow = $view->scroll_visual_row();
    my ($cursor_vrow, $_vcol) = $wm->doc_to_visual(2, 0);
    ok($cursor_vrow >= $scroll_vrow, 'Cursor visible: vrow >= scroll_vrow');
    ok($cursor_vrow < $scroll_vrow + 5, 'Cursor visible: vrow < scroll_vrow + viewport');
};

subtest 'ensure_cursor_visible disables horizontal scroll in wrap mode' => sub {
    my ($view, $doc, $wm) = make_view(10, "short");
    $view->{scroll_col} = 15;  # Set some h-scroll
    $view->set_cursor(0, 0);
    $view->ensure_cursor_visible();
    is($view->{scroll_col}, 0, 'scroll_col reset to 0 in wrap mode');
};

# =============================================================================
# doc_to_screen / screen_to_doc with word wrap
# =============================================================================

subtest 'doc_to_screen with wrap' => sub {
    my ($view, $doc, $wm) = make_view(10, "short", "x" x 25, "end");
    $view->{scroll_line} = 0;

    # Line 0, col 0 → screen row 0
    my ($row, $col) = $view->doc_to_screen(0, 0);
    is($row, 0, 'Line 0 at screen row 0');
    is($col, 0, 'Col 0');

    # Line 1, col 0 → screen row 1
    ($row, $col) = $view->doc_to_screen(1, 0);
    is($row, 1, 'Line 1 first wrap row at screen row 1');

    # Line 1, col 15 → screen row 2 (second wrap row of line 1)
    ($row, $col) = $view->doc_to_screen(1, 15);
    is($row, 2, 'Line 1 second wrap row at screen row 2');

    # Line 2, col 0 → screen row 4
    ($row, $col) = $view->doc_to_screen(2, 0);
    is($row, 4, 'Line 2 at screen row 4');
};

subtest 'screen_to_doc with wrap' => sub {
    my ($view, $doc, $wm) = make_view(10, "short", "x" x 25, "end");
    $view->{scroll_line} = 0;

    # Screen row 0 → line 0
    my ($line, $col) = $view->screen_to_doc(0, 0);
    is($line, 0, 'Screen row 0 = line 0');

    # Screen row 1 → line 1, col 0
    ($line, $col) = $view->screen_to_doc(1, 0);
    is($line, 1, 'Screen row 1 = line 1');
    is($col, 0, 'Col 0');

    # Screen row 2 → line 1 (continuation row)
    ($line, $col) = $view->screen_to_doc(2, 0);
    is($line, 1, 'Screen row 2 = line 1 (continuation)');
    is($col, 10, 'Col 10 (start of second segment)');

    # Screen row 4 → line 2
    ($line, $col) = $view->screen_to_doc(4, 0);
    is($line, 2, 'Screen row 4 = line 2');
};

subtest 'doc_to_screen/screen_to_doc round-trip' => sub {
    my ($view, $doc, $wm) = make_view(10, "hello world this is test", "second line here");
    $view->{scroll_line} = 0;

    for my $test_line (0, 1) {
        my $line_len = $doc->line_length($test_line);
        for my $test_col (0, int($line_len / 2), $line_len) {
            my ($srow, $scol) = $view->doc_to_screen($test_line, $test_col);
            next unless defined $srow;  # Skip if not visible
            my ($dline, $dcol) = $view->screen_to_doc($srow, $scol);
            is($dline, $test_line, "Round-trip line for ($test_line, $test_col)");
            is($dcol, $test_col, "Round-trip col for ($test_line, $test_col)");
        }
    }
};

# =============================================================================
# visible_line_range with word wrap
# =============================================================================

subtest 'visible_line_range with wrap' => sub {
    my ($view, $doc, $wm) = make_view(10, "short", "x" x 100, "end");
    $view->{viewport_rows} = 5;
    $view->{scroll_line} = 0;

    my ($start, $end) = $view->visible_line_range();
    is($start, 0, 'Visible starts at 0');
    # With 5 viewport rows: line 0 = 1 vrow, line 1 starts wrapping.
    # 4 remaining rows show parts of line 1, so visible lines = 0 and 1
    is($end, 2, 'Visible end includes wrapped line');
};

# =============================================================================
# Page up/down with word wrap
# =============================================================================

subtest 'move_page_down with wrap' => sub {
    my ($view, $doc, $wm) = make_view(10, "short", "x" x 100, "end");
    $view->{viewport_rows} = 5;
    $view->set_cursor(0, 0);

    $view->move_page_down();
    # Should have moved by viewport_rows - 1 = 4 visual rows
    my ($vrow, $vcol) = $wm->doc_to_visual($view->cursor_line(), $view->cursor_col());
    is($vrow, 4, 'Page down moved 4 visual rows');
};

subtest 'move_page_up with wrap' => sub {
    my ($view, $doc, $wm) = make_view(10, "short", "x" x 100, "end");
    $view->{viewport_rows} = 5;

    # Start partway through
    $view->set_cursor(1, 50);  # On line 1 deep in wrap
    my ($start_vrow, $_vcol) = $wm->doc_to_visual(1, 50);

    $view->move_page_up();
    my ($vrow, $vcol) = $wm->doc_to_visual($view->cursor_line(), $view->cursor_col());

    my $expected = $start_vrow - 4;
    $expected = 0 if $expected < 0;
    is($vrow, $expected, 'Page up moved back 4 visual rows');
};

# =============================================================================
# Selection across wrap boundaries
# =============================================================================

subtest 'shift+down extends selection across wrap' => sub {
    my ($view, $doc, $wm) = make_view(10, "x" x 25);

    $view->set_cursor(0, 0);
    # Extend selection by moving down with shift
    $view->move_down(1);  # shift=1
    ok($view->has_selection(), 'Selection active after shift+down');

    my ($sl, $sc, $el, $ec) = $view->selection();
    is($sl, 0, 'Selection starts at line 0');
    is($sc, 0, 'Selection starts at col 0');
    is($el, 0, 'Selection ends on line 0 (same line, wrapped)');
    is($ec, 10, 'Selection ends at col 10 (second wrap row)');
};

# =============================================================================
# Cursor affinity at wrap boundaries
# =============================================================================

subtest 'END then Down moves correctly across rows' => sub {
    my ($view, $doc, $wm) = make_view(10, "x" x 25);

    $view->set_cursor(0, 5);

    # END: moves to col_end of first segment (col 10) with 'left' affinity
    $view->move_to_line_end();
    is($view->cursor_col(), 10, 'END at col_end of first segment');
    is($view->cursor_affinity(), 'left', 'Affinity is left after END');

    # doc_to_visual with left affinity: stays on visual row 0
    my ($vrow, $vcol) = $wm->doc_to_visual(0, 10, 'left');
    is($vrow, 0, 'Left affinity keeps cursor on row 0');

    # Down: should move from row 0 to row 1 (not row 2)
    $view->move_down();
    is($view->cursor_col(), 20, 'Down from END moves to row 2 (col 20)');
    is($view->cursor_affinity(), 'right', 'Affinity resets to right after move_down');
};

subtest 'Home at segment boundary with left affinity' => sub {
    my ($view, $doc, $wm) = make_view(10, "x" x 25);

    # END on first wrap row
    $view->set_cursor(0, 5);
    $view->move_to_line_end();
    is($view->cursor_col(), 10, 'At col_end with left affinity');

    # Home should go to start of row 0 (not row 1)
    $view->move_to_line_start();
    is($view->cursor_col(), 0, 'Home from END goes to col 0 (start of same row)');
    is($view->cursor_affinity(), 'right', 'Affinity resets to right after Home');
};

# =============================================================================
# Per-view word wrap override
# =============================================================================

subtest 'word_wrap_override defaults to undef' => sub {
    my ($view, $doc, $wm) = make_view(10, "short");
    is($view->word_wrap_override(), undef, 'Default override is undef');
};

subtest 'set_word_wrap_override persists' => sub {
    my ($view, $doc, $wm) = make_view(10, "short");

    $view->set_word_wrap_override(1);
    is($view->word_wrap_override(), 1, 'Override set to 1');

    $view->set_word_wrap_override(0);
    is($view->word_wrap_override(), 0, 'Override set to 0');

    $view->set_word_wrap_override(undef);
    is($view->word_wrap_override(), undef, 'Override cleared to undef');
};

done_testing();
