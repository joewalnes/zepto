#!/usr/bin/env perl
# Comprehensive tests for Zepto::View
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Zepto::Document;
use Zepto::View;

# Helper to create doc+view
sub make_view {
    my ($text, %opts) = @_;
    my $doc = Zepto::Document->new(text => $text);
    my $view = Zepto::View->new(
        document => $doc,
        viewport_rows => $opts{rows} // 10,
        viewport_cols => $opts{cols} // 40,
    );
    return ($doc, $view);
}

# ============================================================================
# Construction tests
# ============================================================================
subtest 'Construction' => sub {
    my ($doc, $view) = make_view("hello\nworld");

    is($view->cursor_line(), 0, 'Initial cursor line');
    is($view->cursor_col(), 0, 'Initial cursor col');
    ok(!$view->has_selection(), 'No initial selection');
    is($view->scroll_line(), 0, 'Initial scroll line');
    is($view->scroll_col(), 0, 'Initial scroll col');
    is($view->viewport_rows(), 10, 'Viewport rows');
    is($view->viewport_cols(), 40, 'Viewport cols');
};

# ============================================================================
# Cursor movement tests
# ============================================================================
subtest 'Basic cursor movement' => sub {
    my ($doc, $view) = make_view("hello\nworld\ntest");

    $view->move_right();
    is($view->cursor_col(), 1, 'Move right');

    $view->move_down();
    is($view->cursor_line(), 1, 'Move down');
    is($view->cursor_col(), 1, 'Column preserved');

    $view->move_left();
    is($view->cursor_col(), 0, 'Move left');

    $view->move_up();
    is($view->cursor_line(), 0, 'Move up');
};

subtest 'Cursor wrapping' => sub {
    my ($doc, $view) = make_view("ab\ncd");

    # Move right past end of line
    $view->set_cursor(0, 2);  # End of first line
    $view->move_right();
    is($view->cursor_line(), 1, 'Wrapped to next line');
    is($view->cursor_col(), 0, 'At start of line');

    # Move left past start of line
    $view->move_left();
    is($view->cursor_line(), 0, 'Wrapped to prev line');
    is($view->cursor_col(), 2, 'At end of prev line');
};

subtest 'Cursor clamping' => sub {
    my ($doc, $view) = make_view("short\nlooooong\nx");

    # Move down from long to short line
    $view->set_cursor(1, 8);  # End of long line
    $view->move_down();
    is($view->cursor_col(), 1, 'Column clamped to short line');

    # Move back up - should restore preferred column
    $view->move_up();
    is($view->cursor_col(), 8, 'Preferred column restored');
};

subtest 'Cursor at boundaries' => sub {
    my ($doc, $view) = make_view("test");

    $view->move_left();  # Already at 0,0
    is($view->cursor_line(), 0, 'No move past start');
    is($view->cursor_col(), 0, 'No move past start');

    $view->move_up();
    is($view->cursor_line(), 0, 'No move above first line');

    $view->set_cursor(0, 4);  # End
    $view->move_right();
    is($view->cursor_col(), 4, 'No move past last line end');
    is($view->cursor_line(), 0, 'Still on last line');
};

# ============================================================================
# Line navigation tests
# ============================================================================
subtest 'Line start/end' => sub {
    my ($doc, $view) = make_view("hello world");

    $view->set_cursor(0, 5);
    $view->move_to_line_start();
    is($view->cursor_col(), 0, 'Move to line start');

    $view->move_to_line_end();
    is($view->cursor_col(), 11, 'Move to line end');
};

subtest 'Document start/end' => sub {
    my ($doc, $view) = make_view("line1\nline2\nline3");

    $view->set_cursor(1, 3);
    $view->move_to_document_start();
    is($view->cursor_line(), 0, 'Document start line');
    is($view->cursor_col(), 0, 'Document start col');

    $view->move_to_document_end();
    is($view->cursor_line(), 2, 'Document end line');
    is($view->cursor_col(), 5, 'Document end col');
};

subtest 'Page up/down' => sub {
    my ($doc, $view) = make_view("1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12", rows => 5);

    $view->set_cursor(6, 0);
    $view->move_page_up();
    is($view->cursor_line(), 2, 'Page up moves by viewport-1');

    $view->move_page_down();
    is($view->cursor_line(), 6, 'Page down');

    $view->set_cursor(0, 0);
    $view->move_page_up();
    is($view->cursor_line(), 0, 'Page up at top stays at 0');
};

subtest 'Goto line' => sub {
    my ($doc, $view) = make_view("1\n2\n3\n4\n5");

    $view->goto_line(3);  # 1-indexed
    is($view->cursor_line(), 2, 'Goto line 3 (0-indexed = 2)');
    is($view->cursor_col(), 0, 'Goto puts cursor at line start');

    $view->goto_line(100);  # Beyond end
    is($view->cursor_line(), 4, 'Goto clamped to last line');

    $view->goto_line(0);  # Before start
    is($view->cursor_line(), 0, 'Goto 0 goes to first line');
};

# ============================================================================
# Word movement tests
# ============================================================================
subtest 'Word movement' => sub {
    my ($doc, $view) = make_view("hello world test");

    $view->move_word_right();
    is($view->cursor_col(), 6, 'Word right from start');

    $view->move_word_right();
    is($view->cursor_col(), 12, 'Word right again');

    $view->move_word_left();
    is($view->cursor_col(), 6, 'Word left');

    $view->move_word_left();
    is($view->cursor_col(), 0, 'Word left to start');
};

subtest 'Word movement across lines' => sub {
    my ($doc, $view) = make_view("line1\nline2");

    $view->set_cursor(0, 5);  # End of first line
    $view->move_word_right();
    is($view->cursor_line(), 1, 'Word right to next line');
    is($view->cursor_col(), 0, 'At start of next line');

    $view->move_word_left();
    is($view->cursor_line(), 0, 'Word left to prev line');
    is($view->cursor_col(), 5, 'At end of prev line');
};

# ============================================================================
# Selection tests
# ============================================================================
subtest 'Basic selection' => sub {
    my ($doc, $view) = make_view("hello world");

    ok(!$view->has_selection(), 'No selection initially');

    $view->move_right(1);  # extend_selection = true
    ok($view->has_selection(), 'Selection after shift+right');

    my ($sl, $sc, $el, $ec) = $view->selection();
    is($sl, 0, 'Selection start line');
    is($sc, 0, 'Selection start col');
    is($el, 0, 'Selection end line');
    is($ec, 1, 'Selection end col');

    is($view->selected_text(), 'h', 'Selected text');
};

subtest 'Selection cleared on move' => sub {
    my ($doc, $view) = make_view("hello");

    $view->move_right(1);  # Select
    $view->move_right(1);  # Extend
    ok($view->has_selection(), 'Has selection');

    $view->move_right(0);  # No extend - should clear
    ok(!$view->has_selection(), 'Selection cleared');
};

subtest 'Backwards selection' => sub {
    my ($doc, $view) = make_view("hello");

    $view->set_cursor(0, 5);  # End
    $view->move_left(1);
    $view->move_left(1);

    my ($sl, $sc, $el, $ec) = $view->selection();
    # Selection should be normalized (start < end)
    is($sl, 0, 'Normalized start line');
    is($sc, 3, 'Normalized start col');
    is($el, 0, 'Normalized end line');
    is($ec, 5, 'Normalized end col');

    is($view->selected_text(), 'lo', 'Backwards selected text');
};

subtest 'Multi-line selection' => sub {
    my ($doc, $view) = make_view("line1\nline2\nline3");

    $view->set_cursor(0, 3);
    $view->set_cursor(2, 2, 1);  # extend_selection

    my ($sl, $sc, $el, $ec) = $view->selection();
    is($sl, 0, 'Start line');
    is($sc, 3, 'Start col');
    is($el, 2, 'End line');
    is($ec, 2, 'End col');

    is($view->selected_text(), "e1\nline2\nli", 'Multi-line text');
};

subtest 'Select all' => sub {
    my ($doc, $view) = make_view("hello\nworld");

    $view->select_all();
    ok($view->has_selection(), 'Has selection');
    is($view->selected_text(), "hello\nworld", 'All text selected');
};

subtest 'Select word' => sub {
    my ($doc, $view) = make_view("hello world");

    $view->set_cursor(0, 2);  # In middle of 'hello'
    $view->select_word();
    is($view->selected_text(), 'hello', 'Word selected');

    $view->clear_selection();
    $view->set_cursor(0, 6);  # In 'world'
    $view->select_word();
    is($view->selected_text(), 'world', 'Second word selected');
};

subtest 'Select line' => sub {
    my ($doc, $view) = make_view("line1\nline2\nline3");

    $view->set_cursor(1, 2);
    $view->select_line();
    is($view->selected_text(), "line2\n", 'Line with newline selected');

    $view->clear_selection();
    $view->set_cursor(2, 0);  # Last line
    $view->select_line();
    is($view->selected_text(), "line3", 'Last line (no newline) selected');
};

# ============================================================================
# Selection offset tests
# ============================================================================
subtest 'Selection offsets' => sub {
    my ($doc, $view) = make_view("hello\nworld");

    $view->set_cursor(0, 2);
    $view->set_cursor(1, 3, 1);

    my ($start, $end) = $view->selection_offsets();
    is($start, 2, 'Selection start offset');
    is($end, 9, 'Selection end offset');  # "llo\nwor"
};

# ============================================================================
# Viewport tests
# ============================================================================
subtest 'Viewport scrolling' => sub {
    my ($doc, $view) = make_view("1\n2\n3\n4\n5\n6\n7\n8\n9\n10", rows => 3);

    $view->set_cursor(5, 0);  # Line 6 (0-indexed: 5)
    is($view->scroll_line(), 3, 'Scrolled to show cursor');

    my ($start, $end) = $view->visible_line_range();
    is($start, 3, 'Visible start');
    is($end, 6, 'Visible end');
};

subtest 'Horizontal scrolling' => sub {
    my ($doc, $view) = make_view("x" x 100, cols => 20);

    $view->set_cursor(0, 50);
    ok($view->scroll_col() > 0, 'Horizontal scroll active');
    ok($view->scroll_col() <= 50, 'Scroll shows cursor');
};

subtest 'Scroll without cursor move' => sub {
    my ($doc, $view) = make_view("1\n2\n3\n4\n5\n6\n7\n8\n9\n10", rows => 3);

    $view->set_cursor(0, 0);
    $view->scroll_down(2);
    is($view->scroll_line(), 2, 'Scrolled down');
    is($view->cursor_line(), 0, 'Cursor unchanged');

    $view->scroll_up(1);
    is($view->scroll_line(), 1, 'Scrolled up');
};

subtest 'scroll_down clamps so the last line stays pinned at the bottom, not the top' => sub {
    # bugs.md: "Scrolling to the end of a file lets the final line scroll
    # off the top of the viewport, past the point where most editors stop."
    # scroll_down used to clamp scroll_line to line_count()-1, letting the
    # last document line become the TOP of the viewport and leaving the
    # rest of the viewport blank underneath it. It should clamp to
    # line_count()-viewport_rows instead, so the last line lands at the
    # BOTTOM of the viewport and stays there.
    my ($doc, $view) = make_view("1\n2\n3\n4\n5\n6\n7\n8\n9\n10", rows => 4);

    $view->set_cursor(0, 0);
    $view->scroll_down(1000);  # scroll drastically past the end
    is($view->scroll_line(), 6, 'scroll_line clamps to line_count(10) - viewport_rows(4) = 6');

    my ($start, $end) = $view->visible_line_range();
    is($end, 10, 'visible range ends at line_count (exclusive) -- last doc line (index 9) is the bottom row, not scrolled past');

    # A document shorter than the viewport should never scroll at all.
    my ($doc2, $view2) = make_view("1\n2\n3", rows => 10);
    $view2->set_cursor(0, 0);
    $view2->scroll_down(1000);
    is($view2->scroll_line(), 0, 'a document shorter than the viewport never scrolls');
};

subtest 'Scroll sets explicit flag to prevent viewport snap-back' => sub {
    my ($doc, $view) = make_view("1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20", rows => 5);

    # Cursor at top
    $view->set_cursor(0, 0);
    is($view->scroll_line(), 0, 'Start at top');

    # Scroll down past cursor — should NOT snap back on ensure_cursor_visible
    $view->scroll_down(10);
    is($view->scroll_line(), 10, 'Scrolled down by 10');
    is($view->cursor_line(), 0, 'Cursor still at line 0');

    # ensure_cursor_visible should NOT snap back because _explicit_scroll is set
    $view->ensure_cursor_visible();
    is($view->scroll_line(), 10, 'Viewport did NOT snap back after explicit scroll');

    # Flag persists — multiple renders keep viewport scrolled
    $view->ensure_cursor_visible();
    is($view->scroll_line(), 10, 'Viewport still stays after second ensure (flag persists)');

    # clear_explicit_scroll + ensure_cursor_visible SHOULD snap back
    $view->clear_explicit_scroll();
    $view->ensure_cursor_visible();
    is($view->scroll_line(), 0, 'Viewport snaps to cursor after flag cleared');

    # Same test for scroll_up: scroll cursor down, then scroll viewport up past it
    $view->set_cursor(15, 0);
    is($view->scroll_line() + $view->{viewport_rows} > 15, 1, 'Cursor visible');

    $view->scroll_up(100);  # Scroll to top
    is($view->scroll_line(), 0, 'Scrolled up to top');
    is($view->cursor_line(), 15, 'Cursor still at line 15');

    # Flag persists across multiple renders
    $view->ensure_cursor_visible();
    is($view->scroll_line(), 0, 'Viewport stays at top after scroll_up explicit flag');

    $view->ensure_cursor_visible();
    is($view->scroll_line(), 0, 'Viewport still stays after second ensure');

    # Only clears when explicitly cleared (simulating next non-scroll event)
    $view->clear_explicit_scroll();
    $view->ensure_cursor_visible();
    ok($view->scroll_line() > 0, 'Viewport snaps to cursor after flag cleared');
};

subtest 'Set viewport size' => sub {
    my ($doc, $view) = make_view("1\n2\n3\n4\n5\n6\n7\n8\n9\n10", rows => 10);

    $view->set_cursor(8, 0);  # Near bottom
    is($view->scroll_line(), 0, 'No scroll needed with 10 rows');

    $view->set_viewport_size(3, 40);  # Shrink viewport
    ok($view->scroll_line() > 0, 'Scroll adjusted for smaller viewport');
};

# ============================================================================
# Coordinate conversion tests
# ============================================================================
subtest 'Doc to screen conversion' => sub {
    my ($doc, $view) = make_view("1\n2\n3\n4\n5\n6\n7\n8\n9\n10", rows => 3);

    $view->set_cursor(3, 0);  # Scroll to show line 3

    my ($row, $col) = $view->doc_to_screen(3, 0);
    ok(defined $row, 'Line 3 is visible');

    ($row, $col) = $view->doc_to_screen(0, 0);
    is($row, undef, 'Line 0 not visible after scroll');
};

subtest 'Screen to doc conversion' => sub {
    my ($doc, $view) = make_view("hello\nworld", rows => 10);

    my ($line, $col) = $view->screen_to_doc(0, 0);
    is($line, 0, 'Screen 0,0 -> line 0');
    is($col, 0, 'Screen 0,0 -> col 0');

    ($line, $col) = $view->screen_to_doc(1, 3);
    is($line, 1, 'Screen 1,3 -> line 1');
    is($col, 3, 'Screen 1,3 -> col 3');

    ($line, $col) = $view->screen_to_doc(1, 100);
    is($col, 5, 'Col clamped to line length');
};

# ============================================================================
# is_selected tests
# ============================================================================
subtest 'is_selected' => sub {
    my ($doc, $view) = make_view("hello\nworld");

    $view->set_cursor(0, 1);
    $view->set_cursor(0, 4, 1);  # Select "ell"

    ok($view->is_selected(0, 1), 'Start of selection');
    ok($view->is_selected(0, 2), 'Middle of selection');
    ok($view->is_selected(0, 3), 'End of selection');
    ok(!$view->is_selected(0, 0), 'Before selection');
    ok(!$view->is_selected(0, 4), 'After selection');
    ok(!$view->is_selected(1, 0), 'Different line');
};

# ============================================================================
# Cursor offset tests
# ============================================================================
subtest 'Cursor offset' => sub {
    my ($doc, $view) = make_view("hello\nworld");

    $view->set_cursor(0, 3);
    is($view->cursor_offset(), 3, 'Cursor offset first line');

    $view->set_cursor(1, 2);
    is($view->cursor_offset(), 8, 'Cursor offset second line');  # 6 (hello\n) + 2

    $view->set_cursor_from_offset(4);
    is($view->cursor_line(), 0, 'Set from offset - line');
    is($view->cursor_col(), 4, 'Set from offset - col');
};

# ============================================================================
# Edge cases
# ============================================================================
subtest 'Empty document' => sub {
    my ($doc, $view) = make_view("");

    is($view->cursor_line(), 0, 'Cursor at 0,0');
    is($view->cursor_col(), 0, 'Cursor at 0,0');

    $view->move_right();
    is($view->cursor_col(), 0, 'Cannot move in empty doc');

    $view->select_all();
    is($view->selected_text(), '', 'Empty selection');
};

subtest 'Single character' => sub {
    my ($doc, $view) = make_view("x");

    $view->move_right();
    is($view->cursor_col(), 1, 'Move to after char');

    $view->move_right();
    is($view->cursor_col(), 1, 'Cannot move past end');
};

# ============================================================================
# Horizontal scrolling - cursor stays in comfortable zone
# ============================================================================
subtest 'Horizontal scroll keeps cursor in sweet spot' => sub {
    # Create a long line (100 chars) with narrow viewport (40 cols)
    my $long_line = 'A' x 100;
    my ($doc, $view) = make_view($long_line, cols => 40);

    is($view->scroll_col(), 0, 'Initially no horizontal scroll');

    # Move cursor past 75% of viewport (30 chars) - should trigger scroll
    $view->set_cursor(0, 35);
    ok($view->scroll_col() > 0, 'Scrolled when cursor past 75% of viewport');

    # Cursor should be around 75% from left (target position)
    my $cursor_screen_pos = $view->cursor_col() - $view->scroll_col();
    ok($cursor_screen_pos <= 30, "Cursor kept in sweet spot (screen pos $cursor_screen_pos)");

    # Move to far right of document
    $view->set_cursor(0, 95);
    ok($view->scroll_col() > 50, 'Scrolled significantly for far position');

    # Move back to start - scroll should reset
    $view->set_cursor(0, 0);
    is($view->scroll_col(), 0, 'Scroll reset when cursor at start');
};

subtest 'Horizontal scroll left margin' => sub {
    my $long_line = 'B' x 100;
    my ($doc, $view) = make_view($long_line, cols => 40);

    # Move far right first
    $view->set_cursor(0, 80);
    my $scroll_at_80 = $view->scroll_col();
    ok($scroll_at_80 > 0, 'Scrolled right');

    # Now move left - cursor stays visible with some left context
    $view->set_cursor(0, 50);

    # Cursor should have some distance from left edge (20% zone = 8 chars)
    my $distance_from_left = $view->cursor_col() - $view->scroll_col();
    ok($distance_from_left >= 4, "Cursor kept from left edge (got $distance_from_left)");
};

subtest 'Long line navigation' => sub {
    my $long_line = '0123456789' x 10;  # 100 chars: 0123456789 repeated
    my ($doc, $view) = make_view($long_line, cols => 40);

    # Navigate with arrow keys across the line
    for (1..50) {
        $view->move_right();
    }
    is($view->cursor_col(), 50, 'Cursor at column 50');

    # Cursor should be visible with context on both sides
    my $scol = $view->scroll_col();
    ok($view->cursor_col() >= $scol, 'Cursor visible (not before scroll)');
    ok($view->cursor_col() < $scol + 40, 'Cursor visible (not after viewport)');
};

subtest 'Scroll shows line end when approaching EOL' => sub {
    my $long_line = 'X' x 100;  # 100 char line
    my ($doc, $view) = make_view($long_line, cols => 40);

    # Move to near end of line (within 40% of viewport from EOL)
    $view->set_cursor(0, 90);  # 10 chars from end, within 40% zone (16 chars)

    # Should scroll to show line end
    my $scol = $view->scroll_col();
    my $visible_end = $scol + 40;
    ok($visible_end >= 100, "Line end visible when cursor near EOL (visible_end=$visible_end)");

    # Move to exact end
    $view->set_cursor(0, 100);
    $scol = $view->scroll_col();
    $visible_end = $scol + 40;
    ok($visible_end >= 100, "Line end visible at EOL");
};

# ============================================================================
# Sticky/goal column tests (ASKS.md item 2, 2026-09-01)
#
# View tracks _preferred_col as a "goal" column that survives vertical
# movement through shorter lines, so arrowing back to a longer line
# restores the original horizontal position instead of "jumping around"
# to wherever the short line happened to leave the cursor. These tests
# pin down the exact contract:
#   - vertical movement (up/down/pageup/pagedown) preserves the goal
#   - horizontal movement (left/right) and explicit repositioning
#     (Home/End) RESET the goal to the new real column
#   - the cursor's real column is always clamped to true end-of-line
#     (never drawn past the text) even while a taller goal is retained
# ============================================================================

subtest 'Sticky column survives a shorter line and restores on a longer one' => sub {
    my ($doc, $view) = make_view("looooooooooooong line one\nsh\ntiny\nlooooooooooooong line two again");

    $view->set_cursor(0, 20);
    is($view->cursor_col(), 20, 'Start at col 20 on long line');

    $view->move_down();
    is($view->cursor_line(), 1, 'Moved to short line');
    is($view->cursor_col(), 2, 'Column clamped to short line end (true end, not past it)');

    $view->move_down();
    is($view->cursor_line(), 2, 'Moved to tiny line');
    is($view->cursor_col(), 4, 'Column clamped to tiny line end');

    $view->move_down();
    is($view->cursor_line(), 3, 'Moved to second long line');
    is($view->cursor_col(), 20, 'Goal column (20) restored exactly, not left at 4');

    # And the reverse direction restores it too.
    $view->move_up();
    $view->move_up();
    $view->move_up();
    is($view->cursor_line(), 0, 'Back on first long line');
    is($view->cursor_col(), 20, 'Goal column (20) still intact after round trip');
};

subtest 'End key sets goal column to the true (real) line end, not a fixed large number' => sub {
    my ($doc, $view) = make_view("short one\nreally quite a lot longer than the first\nx");

    $view->set_cursor(0, 3);
    $view->move_to_line_end();
    is($view->cursor_col(), 9, 'End lands at true end of short line (9 chars)');

    # Goal is now 9 (the line-1 end), NOT some large sentinel. Moving down
    # to the much longer line 2 must land at col 9, not at line 2's own end.
    $view->move_down();
    is($view->cursor_line(), 1, 'Moved to longer line');
    is($view->cursor_col(), 9, 'Landed at col 9 (End-derived goal), proving End did not set an oversized goal');
};

subtest 'Horizontal movement (left/right) resets the goal column' => sub {
    my ($doc, $view) = make_view("looooooooooooong line one\nsh\nlooooooooooooong line two again");

    $view->set_cursor(0, 20);
    $view->move_down();
    is($view->cursor_col(), 2, 'Pinned at true end of short line (goal 20 still remembered internally)');

    # Explicit horizontal repositioning: goal must now become 1 (real col
    # after moving left), NOT stay at the old value of 20.
    $view->move_left();
    is($view->cursor_col(), 1, 'Moved left to col 1');

    $view->move_down();
    is($view->cursor_line(), 2, 'Moved to second long line');
    is($view->cursor_col(), 1, 'Landed at col 1 (new goal from left-arrow), not the stale 20');

    # move_right also resets the goal.
    $view->set_cursor(0, 20);
    $view->move_down();
    $view->move_right();  # short line has 2 chars; col 2 is EOL, move_right wraps to next line start
    is($view->cursor_line(), 2, 'Right-arrow at EOL of short line wraps to next line');
    is($view->cursor_col(), 0, 'Lands at col 0 of next line');
    $view->move_down();
    is($view->cursor_col(), 0, 'Goal reset to 0 by the right-arrow wrap, not left at 20');
};

subtest 'Home resets the goal column to where it lands' => sub {
    my ($doc, $view) = make_view("    indented one\nlong second line here\nsh");

    $view->set_cursor(1, 10);
    $view->move_to_line_start();  # smart-home: first non-ws (col 0, no leading ws) -> col 0
    is($view->cursor_col(), 0, 'Home lands at col 0 (no indent on this line)');

    $view->move_down();
    is($view->cursor_line(), 2, 'Moved to short line');
    is($view->cursor_col(), 0, 'Goal reset to 0 by Home, so short line lands at col 0 too');
};

subtest 'Typing while pinned past a short line snaps to true end, does not pad with whitespace' => sub {
    my ($doc, $view) = make_view("a very much longer first line indeed\nhi");

    $view->set_cursor(0, 25);
    $view->move_down();
    is($view->cursor_line(), 1, 'Moved to short line');
    is($view->cursor_col(), 2, 'Pinned at true end of "hi" (col 2), not padded out to col 25');

    # Mirror what Editor::do_insert_char does: insert at the CURRENT
    # (already-clamped) cursor position, then advance.
    my $offset = $doc->line_col_to_offset($view->cursor_line(), $view->cursor_col());
    $doc->insert($offset, 'X');
    $view->move_right();

    is($doc->get_line_content(1), 'hiX', 'Character inserted at true end - no padding whitespace before it');
    is($view->cursor_col(), 3, 'Cursor now at true col 3 (right after typed char)');
    is($view->{_preferred_col}, 3, 'Goal column updated to match the new real position (3, not 25)');
};

subtest 'Page up/down respect the goal column, same as arrow keys' => sub {
    my ($doc, $view) = make_view(
        "loooooooooooooooooooooong line 0\n" .
        "s1\ns2\ns3\ns4\n" .
        "loooooooooooooooooooooong line 5",
        rows => 3
    );
    # viewport_rows=3 -> page_size = viewport_rows-1 = 2

    $view->set_cursor(0, 25);
    $view->move_page_down();
    is($view->cursor_line(), 2, 'Page down moved 2 lines (page_size)');
    is($view->cursor_col(), 2, 'Column clamped to short line "s2" end');

    $view->move_page_down();
    is($view->cursor_line(), 4, 'Page down again to s4');
    is($view->cursor_col(), 2, 'Column clamped to short line "s4" end');

    $view->move_page_down();
    is($view->cursor_line(), 5, 'Page down lands on the long line at the end (clamped by doc bounds)');
    is($view->cursor_col(), 25, 'Goal column (25) restored on the long line, not left at 2');

    $view->move_page_up();
    $view->move_page_up();
    $view->move_page_up();
    is($view->cursor_line(), 0, 'Page up back to the first long line');
    is($view->cursor_col(), 25, 'Goal column (25) still intact after a page up/down round trip');
};

done_testing();
