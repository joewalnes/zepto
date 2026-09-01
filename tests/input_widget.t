#!/usr/bin/env perl
# Tests for Zepto::InputWidget — unified text input widget
use strict;
use warnings;
use Test::More;
use lib 'lib';

use Zepto::InputWidget;

# Helper to make a key event with modifiers
sub key_event {
    my ($key, @mods) = @_;
    return { type => 'key', key => $key, modifiers => \@mods };
}

# Helper to make a char event with modifiers
sub char_event {
    my ($char, @mods) = @_;
    return { type => 'char', char => $char, modifiers => \@mods };
}

# =============================================================================
# Construction
# =============================================================================

subtest 'new creates widget with empty value' => sub {
    my $w = Zepto::InputWidget->new();
    is($w->value(), '', 'Default value is empty string');
    is($w->cursor(), 0, 'Default cursor is 0');
    ok(!$w->has_selection(), 'No selection by default');
};

subtest 'new with initial value places cursor at end' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    is($w->value(), 'hello', 'Value set');
    is($w->cursor(), 5, 'Cursor at end');
};

# =============================================================================
# Basic char insertion
# =============================================================================

subtest 'Char insertion at end' => sub {
    my $w = Zepto::InputWidget->new();
    $w->handle_event(char_event('a'));
    $w->handle_event(char_event('b'));
    $w->handle_event(char_event('c'));
    is($w->value(), 'abc', 'Three chars inserted');
    is($w->cursor(), 3, 'Cursor at end');
};

subtest 'Char insertion in middle' => sub {
    my $w = Zepto::InputWidget->new(value => 'ac');
    $w->{cursor} = 1;  # position between a and c
    $w->handle_event(char_event('b'));
    is($w->value(), 'abc', 'Char inserted in middle');
    is($w->cursor(), 2, 'Cursor advanced');
};

# =============================================================================
# Arrow key cursor movement
# =============================================================================

subtest 'Left/right arrow moves cursor' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    is($w->cursor(), 5, 'Start at end');
    $w->handle_event(key_event('left'));
    is($w->cursor(), 4, 'Moved left');
    $w->handle_event(key_event('right'));
    is($w->cursor(), 5, 'Moved right');
};

subtest 'Left arrow stops at 0' => sub {
    my $w = Zepto::InputWidget->new(value => 'hi');
    $w->{cursor} = 0;
    $w->handle_event(key_event('left'));
    is($w->cursor(), 0, 'Cursor clamped at 0');
};

subtest 'Right arrow stops at end' => sub {
    my $w = Zepto::InputWidget->new(value => 'hi');
    $w->handle_event(key_event('right'));
    is($w->cursor(), 2, 'Cursor clamped at end');
};

subtest 'Home/End move cursor' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_event(key_event('home'));
    is($w->cursor(), 0, 'Home goes to start');
    $w->handle_event(key_event('end'));
    is($w->cursor(), 5, 'End goes to end');
};

# =============================================================================
# Word movement (Alt+Left/Right) — PREVIOUSLY MISSING
# =============================================================================

subtest 'Alt+Left moves by word' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello world');
    # cursor at end (11)
    $w->handle_event(key_event('left', 'alt'));
    is($w->cursor(), 6, 'Moved to start of "world"');
    $w->handle_event(key_event('left', 'alt'));
    is($w->cursor(), 0, 'Moved to start of "hello"');
};

subtest 'Alt+Right moves by word' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello world');
    $w->{cursor} = 0;
    $w->handle_event(key_event('right', 'alt'));
    is($w->cursor(), 5, 'Moved to end of "hello"');
    $w->handle_event(key_event('right', 'alt'));
    is($w->cursor(), 11, 'Moved to end of "world"');
};

subtest 'Alt+Left skips leading whitespace then word' => sub {
    my $w = Zepto::InputWidget->new(value => 'foo  bar');
    $w->{cursor} = 8;  # end
    $w->handle_event(key_event('left', 'alt'));
    is($w->cursor(), 5, 'Skipped whitespace, at start of "bar"');
};

# =============================================================================
# Backspace and Delete
# =============================================================================

subtest 'Backspace removes before cursor' => sub {
    my $w = Zepto::InputWidget->new(value => 'abc');
    $w->handle_event(key_event('backspace'));
    is($w->value(), 'ab', 'Last char removed');
    is($w->cursor(), 2, 'Cursor moved back');
};

subtest 'Delete removes after cursor' => sub {
    my $w = Zepto::InputWidget->new(value => 'abc');
    $w->{cursor} = 1;
    $w->handle_event(key_event('delete'));
    is($w->value(), 'ac', 'Char after cursor removed');
    is($w->cursor(), 1, 'Cursor unchanged');
};

subtest 'Backspace at start does nothing' => sub {
    my $w = Zepto::InputWidget->new(value => 'ab');
    $w->{cursor} = 0;
    $w->handle_event(key_event('backspace'));
    is($w->value(), 'ab', 'Value unchanged');
    is($w->cursor(), 0, 'Cursor unchanged');
};

# =============================================================================
# Selection with Shift — PREVIOUSLY MISSING
# =============================================================================

subtest 'Shift+Right extends selection' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->{cursor} = 0;
    $w->handle_event(key_event('right', 'shift'));
    ok($w->has_selection(), 'Selection active');
    my ($s, $e) = $w->selection_range();
    is($s, 0, 'Selection starts at 0');
    is($e, 1, 'Selection ends at 1');
    is($w->cursor(), 1, 'Cursor at 1');
};

subtest 'Shift+Left extends selection leftward' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    # cursor at end
    $w->handle_event(key_event('left', 'shift'));
    $w->handle_event(key_event('left', 'shift'));
    ok($w->has_selection(), 'Selection active');
    my ($s, $e) = $w->selection_range();
    is($s, 3, 'Selection normalized start');
    is($e, 5, 'Selection normalized end');
};

subtest 'Shift+Home selects to start' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    # cursor at end (5)
    $w->handle_event(key_event('home', 'shift'));
    ok($w->has_selection(), 'Selection active');
    my ($s, $e) = $w->selection_range();
    is($s, 0, 'Selection from 0');
    is($e, 5, 'Selection to 5');
};

subtest 'Shift+End selects to end' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->{cursor} = 0;
    $w->handle_event(key_event('end', 'shift'));
    ok($w->has_selection(), 'Selection active');
    my ($s, $e) = $w->selection_range();
    is($s, 0, 'Selection from 0');
    is($e, 5, 'Selection to 5');
};

subtest 'Shift+Alt+Right selects by word' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello world');
    $w->{cursor} = 0;
    $w->handle_event(key_event('right', 'shift', 'alt'));
    ok($w->has_selection(), 'Selection active');
    my ($s, $e) = $w->selection_range();
    is($s, 0, 'Selection starts at 0');
    is($e, 5, 'Selection ends after "hello"');
};

subtest 'Shift+Alt+Left selects by word leftward' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello world');
    # cursor at end (11)
    $w->handle_event(key_event('left', 'shift', 'alt'));
    ok($w->has_selection(), 'Selection active');
    my ($s, $e) = $w->selection_range();
    is($s, 6, 'Selection starts at "world"');
    is($e, 11, 'Selection ends at end');
};

subtest 'Left arrow with selection collapses to selection start' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->{cursor} = 0;
    # Select "hel"
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right', 'shift'));
    ok($w->has_selection(), 'Selection active');
    $w->handle_event(key_event('left'));
    ok(!$w->has_selection(), 'Selection cleared');
    is($w->cursor(), 0, 'Cursor at selection start');
};

subtest 'Right arrow with selection collapses to selection end' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->{cursor} = 0;
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right'));
    ok(!$w->has_selection(), 'Selection cleared');
    is($w->cursor(), 3, 'Cursor at selection end');
};

subtest 'Backspace with selection deletes it' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello world');
    $w->{cursor} = 0;
    # Select "hello"
    $w->handle_event(key_event('end', 'shift'));
    # Wait that selects whole string. Let's just select first 5 chars:
    my $w2 = Zepto::InputWidget->new(value => 'hello world');
    $w2->{cursor} = 0;
    $w2->handle_event(key_event('right', 'shift'));
    $w2->handle_event(key_event('right', 'shift'));
    $w2->handle_event(key_event('right', 'shift'));
    $w2->handle_event(key_event('right', 'shift'));
    $w2->handle_event(key_event('right', 'shift'));  # select "hello"
    $w2->handle_event(key_event('backspace'));
    is($w2->value(), ' world', 'Selection deleted');
    is($w2->cursor(), 0, 'Cursor at deletion point');
    ok(!$w2->has_selection(), 'No selection after delete');
};

subtest 'Typing replaces selection' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->{cursor} = 0;
    $w->handle_event(key_event('end', 'shift'));  # select all
    $w->handle_event(char_event('x'));
    is($w->value(), 'x', 'Selection replaced');
    is($w->cursor(), 1, 'Cursor after inserted char');
};

# =============================================================================
# Ctrl+A — Select All — PREVIOUSLY MISSING
# =============================================================================

subtest 'Ctrl+A selects all' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello world');
    $w->{cursor} = 3;
    $w->handle_event(char_event('a', 'ctrl'));
    ok($w->has_selection(), 'Selection active');
    my ($s, $e) = $w->selection_range();
    is($s, 0, 'Selection from start');
    is($e, 11, 'Selection to end');
    is($w->cursor(), 11, 'Cursor at end');
};

# =============================================================================
# Clipboard operations — PREVIOUSLY MISSING
# =============================================================================

subtest 'Ctrl+X cuts selection' => sub {
    my $clipboard = '';
    my $w = Zepto::InputWidget->new(value => 'hello world');
    $w->{cursor} = 0;
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right', 'shift'));
    $w->handle_event(key_event('right', 'shift'));  # select "hello"
    $w->handle_event(char_event('x', 'ctrl'), \$clipboard);
    is($clipboard, 'hello', 'Clipboard contains selection');
    is($w->value(), ' world', 'Selection removed from value');
    ok(!$w->has_selection(), 'No selection after cut');
};

subtest 'Ctrl+C copies selection without removing it' => sub {
    my $clipboard = '';
    my $w = Zepto::InputWidget->new(value => 'hello world');
    $w->{cursor} = 0;
    $w->handle_event(char_event('a', 'ctrl'));  # select all
    $w->handle_event(char_event('c', 'ctrl'), \$clipboard);
    is($clipboard, 'hello world', 'Clipboard contains selection');
    is($w->value(), 'hello world', 'Value unchanged after copy');
    ok($w->has_selection(), 'Selection still active after copy');
};

subtest 'Ctrl+V pastes at cursor' => sub {
    my $clipboard = 'world';
    my $w = Zepto::InputWidget->new(value => 'hello ');
    $w->handle_event(char_event('v', 'ctrl'), \$clipboard);
    is($w->value(), 'hello world', 'Text pasted at end');
    is($w->cursor(), 11, 'Cursor after pasted text');
};

subtest 'Ctrl+V replaces selection' => sub {
    my $clipboard = 'world';
    my $w = Zepto::InputWidget->new(value => 'hello there');
    $w->{cursor} = 6;
    # Select "there"
    $w->handle_event(key_event('end', 'shift'));
    $w->handle_event(char_event('v', 'ctrl'), \$clipboard);
    is($w->value(), 'hello world', 'Selection replaced by paste');
};

subtest 'Ctrl+X with no selection does nothing' => sub {
    my $clipboard = 'existing';
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_event(char_event('x', 'ctrl'), \$clipboard);
    is($clipboard, 'existing', 'Clipboard unchanged');
    is($w->value(), 'hello', 'Value unchanged');
};

subtest 'Ctrl+V with empty clipboard does nothing' => sub {
    my $clipboard = '';
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_event(char_event('v', 'ctrl'), \$clipboard);
    is($w->value(), 'hello', 'Value unchanged with empty clipboard');
};

# =============================================================================
# Special key pass-through
# =============================================================================

subtest 'Enter not handled by widget' => sub {
    my $w = Zepto::InputWidget->new(value => 'test');
    my $handled = $w->handle_event(key_event('enter'));
    is($handled, 0, 'Enter not handled — caller must handle it');
};

subtest 'Escape not handled by widget' => sub {
    my $w = Zepto::InputWidget->new(value => 'test');
    my $handled = $w->handle_event(key_event('escape'));
    is($handled, 0, 'Escape not handled — caller must handle it');
};

subtest 'Tab not handled by widget' => sub {
    my $w = Zepto::InputWidget->new(value => 'test');
    my $handled = $w->handle_event(key_event('tab'));
    is($handled, 0, 'Tab not handled — caller must handle it');
};

subtest 'Unknown ctrl+char not handled by widget' => sub {
    my $w = Zepto::InputWidget->new(value => 'test');
    my $handled = $w->handle_event(char_event('r', 'ctrl'));
    is($handled, 0, 'Unknown ctrl+char not handled');
};

# =============================================================================
# set_value helper
# =============================================================================

subtest 'set_value updates value and resets cursor' => sub {
    my $w = Zepto::InputWidget->new(value => 'old');
    $w->{cursor} = 1;
    $w->set_value('new value');
    is($w->value(), 'new value', 'Value updated');
    is($w->cursor(), 9, 'Cursor at end of new value');
    ok(!$w->has_selection(), 'Selection cleared');
};

# =============================================================================
# selected_text helper
# =============================================================================

subtest 'selected_text returns selected range' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello world');
    $w->{cursor} = 0;
    $w->handle_event(char_event('a', 'ctrl'));  # select all
    is($w->selected_text(), 'hello world', 'selected_text returns full string');
};

subtest 'selected_text returns empty with no selection' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    is($w->selected_text(), '', 'No selection returns empty string');
};

# =============================================================================
# viewport() — overflow scrolling
# =============================================================================

subtest 'viewport fits entire value when short enough' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    my $vp = $w->viewport(10);
    is($vp->{display_text},   'hello', 'Full text shown');
    is($vp->{cursor_in_view}, 5,       'Cursor at position 5');
    is($vp->{view_offset},    0,       'No scroll offset');
    ok(!defined $vp->{sel_start_in_view}, 'No selection');
};

subtest 'viewport scrolls to keep cursor visible when at end' => sub {
    my $w = Zepto::InputWidget->new(value => 'abcdefghij');  # 10 chars
    # cursor at 10 (end), width 5 → vo = 10-5+1 = 6
    # display = substr(val, 6, 5) = 'ghij' (only 4 chars remain)
    # cursor_in_view = 10 - 6 = 4 (after last visible char)
    my $vp = $w->viewport(5);
    is($vp->{display_text},   'ghij', 'Shows trailing chars');
    is($vp->{cursor_in_view}, 4,      'Cursor after last visible char');
    is($vp->{view_offset},    6,      'Scrolled right');
};

subtest 'viewport scrolls left when cursor moves to start' => sub {
    my $w = Zepto::InputWidget->new(value => 'abcdefghij');  # 10 chars
    $w->{cursor} = 0;
    my $vp = $w->viewport(5);
    is($vp->{display_text},   'abcde', 'Shows first 5 chars');
    is($vp->{cursor_in_view}, 0,       'Cursor at left edge');
    is($vp->{view_offset},    0,       'No offset');
};

subtest 'viewport keeps cursor visible when in middle' => sub {
    my $w = Zepto::InputWidget->new(value => 'abcdefghij');  # 10 chars
    $w->{cursor} = 5;
    my $vp = $w->viewport(5);
    # cursor=5, width=5: need vo such that 5 in [vo, vo+4]
    # vo=1 would give cursor_in_view=4, or vo=5 gives cursor_in_view=0
    # but vo starts at 0, cursor=5 >= 0+5=5, so vo = 5-5+1 = 1
    is($vp->{cursor_in_view}, 4, 'Cursor in view');
    ok($vp->{view_offset} <= 5, 'Scroll within range');
    ok($vp->{view_offset} >= 1, 'Scrolled past start');
};

subtest 'viewport min width is 1 does not crash' => sub {
    my $w = Zepto::InputWidget->new(value => 'abc');
    my $vp = $w->viewport(0);  # clamped to 1
    ok(defined $vp->{display_text}, 'Returns display_text without dying');
    ok(defined $vp->{cursor_in_view}, 'Returns cursor_in_view without dying');
};

subtest 'viewport returns selection bounds clipped to view' => sub {
    my $w = Zepto::InputWidget->new(value => 'abcdefghij');  # 10 chars
    $w->{cursor}    = 10;
    $w->{sel_start} = 0;
    $w->{sel_end}   = 10;
    # cursor=10, width=5 → vo = 6, display='ghij' (4 chars)
    # sel: ev = 10-6=4, sv = 0-6=-6 → clipped to (0, 4)
    my $vp = $w->viewport(5);
    is($vp->{sel_start_in_view}, 0, 'Selection start clipped to view left');
    is($vp->{sel_end_in_view},   4, 'Selection end at last visible position');
};

subtest 'viewport selection entirely off left returns undef bounds' => sub {
    my $w = Zepto::InputWidget->new(value => 'abcdefghij');  # 10 chars
    # selection covers chars 0..2, cursor at end so view shows 5..9
    $w->{sel_start} = 0;
    $w->{sel_end}   = 2;
    $w->{cursor}    = 10;
    my $vp = $w->viewport(5);
    ok(!defined $vp->{sel_start_in_view}, 'Off-screen selection not shown');
};

subtest 'viewport updates view_offset persistently' => sub {
    my $w = Zepto::InputWidget->new(value => 'abcdefghij');
    $w->viewport(5);  # cursor at end → vo set to 5 (or 6?)
    my $first_offset = $w->view_offset();
    $w->viewport(5);  # calling again must give same result
    is($w->view_offset(), $first_offset, 'view_offset stable across calls');
};

# bugs.md P2 "Shift+Tab in the find/replace bar drops the last character
# of BOTH the Find and Replace field values" -- root cause traced to
# viewport() leaving a stale view_offset in place after a caller passes a
# transiently narrower $width (e.g. the find bar shrinks its input field
# by the length of "..." for the single render frame where the find
# engine's is_searching flag is momentarily true), then widens back out.
# The stale offset used to persist because the scroll-into-view check
# only reacts when the cursor falls OUTSIDE [vo, vo+width) -- it never
# notices that a smaller/zero vo would now show strictly more of a value
# that fits entirely within the new width. These tests reproduce the
# narrow-then-wide call sequence directly against InputWidget, without
# needing the full find bar / renderer machinery, and assert the widget
# self-corrects once the value fits again -- i.e. no character is ever
# hidden from view that doesn't need to be.
subtest 'viewport self-corrects stale view_offset once value fits again' => sub {
    my $w = Zepto::InputWidget->new(value => 'aaa');  # 3 chars, cursor at end (3)
    # Simulate one transient render frame at a width narrower than the
    # value (2 < 3) -- e.g. the find bar's match-count text growing by
    # "..." for the single render where the find engine's is_searching
    # flag is momentarily true, shrinking the shared input_width. This
    # legitimately can't show the whole value and scrolls, same as any
    # overflowing field.
    my $vp_narrow = $w->viewport(2);
    is($vp_narrow->{view_offset}, 2, 'Narrow-frame call scrolls view_offset (sanity check)');
    is($vp_narrow->{display_text}, 'a', 'Narrow frame itself cannot show the full value (expected overflow)');

    # Next frame: width widens back to 4 (search finished, "..." gone),
    # and the full 3-char value now fits inside it. Before the fix, the
    # stale view_offset=2 stuck because cursor(3) still fit inside
    # [2, 2+4)=[2,6), so nothing corrected it, and this call still hid
    # the first two characters even though the whole value now fits --
    # the exact bug: "aaa" rendered as a single trailing character while
    # $w->{value} itself was never touched.
    my $vp_wide = $w->viewport(4);
    is($vp_wide->{display_text}, 'aaa', 'Widened frame shows the full value again, not truncated');
    is($vp_wide->{view_offset}, 0, 'view_offset resets to 0 once the full value fits');
    is($w->value(), 'aaa', 'Underlying value was never touched by any viewport() call');
};

subtest 'viewport resets stale offset to 0 whenever full value fits width' => sub {
    my $w = Zepto::InputWidget->new(value => 'bbb');
    # Force a stale, larger-than-necessary view_offset directly (as if
    # left over from an earlier narrower/different-cursor render) and
    # confirm viewport() does not trust it once the value fits.
    $w->{view_offset} = 2;
    my $vp = $w->viewport(10);
    is($vp->{display_text}, 'bbb', 'Full value shown despite stale view_offset');
    is($vp->{view_offset}, 0, 'Stale view_offset corrected to 0');
};

subtest 'viewport does not disturb legitimate end-of-value scroll for long values' => sub {
    # Guards against an overly broad fix: when the value is genuinely
    # longer than the field (len > width), the deliberate "one empty
    # trailing cell at cursor" behavior (see 'viewport scrolls to keep
    # cursor visible when at end' above) must be unaffected by the
    # len<=width self-correction added for the bug above.
    my $w = Zepto::InputWidget->new(value => 'abcdefghij');  # 10 chars
    my $vp = $w->viewport(5);
    is($vp->{display_text}, 'ghij', 'Still shows trailing chars for an overflowing value');
    is($vp->{view_offset}, 6, 'Still scrolls right as before (unaffected by the fix)');
};

# =============================================================================
# Mouse: click to place cursor
# =============================================================================

subtest 'handle_mouse_click places cursor at char_offset' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_mouse_click(2);
    is($w->cursor(), 2, 'Cursor placed at offset 2');
    ok(!$w->has_selection(), 'No selection after click');
};

subtest 'handle_mouse_click clamps to 0' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_mouse_click(-5);
    is($w->cursor(), 0, 'Cursor clamped at 0');
};

subtest 'handle_mouse_click clamps to end' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_mouse_click(100);
    is($w->cursor(), 5, 'Cursor clamped at end');
};

subtest 'handle_mouse_click accounts for view_offset' => sub {
    my $w = Zepto::InputWidget->new(value => 'abcdefghij');
    $w->{view_offset} = 5;  # showing chars 5..9
    $w->handle_mouse_click(2);  # click at column 2 within the view
    is($w->cursor(), 7, 'Cursor = view_offset + char_offset');
};

subtest 'handle_mouse_click clears existing selection' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->{sel_start} = 0;
    $w->{sel_end}   = 3;
    $w->handle_mouse_click(1);
    ok(!$w->has_selection(), 'Selection cleared on click');
};

# =============================================================================
# Mouse: drag to select
# =============================================================================

subtest 'drag from click point creates selection' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_mouse_click(1);        # press at col 1
    $w->handle_mouse_drag_update(3);  # drag to col 3
    ok($w->has_selection(), 'Selection active during drag');
    my ($s, $e) = $w->selection_range();
    is($s, 1, 'Selection starts at press point');
    is($e, 3, 'Selection ends at drag point');
    is($w->cursor(), 3, 'Cursor at drag point');
};

subtest 'drag back to origin clears selection' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_mouse_click(2);
    $w->handle_mouse_drag_update(4);
    $w->handle_mouse_drag_update(2);  # back to origin
    ok(!$w->has_selection(), 'Selection cleared when drag returns to origin');
};

subtest 'handle_mouse_drag_end clears drag_anchor' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->handle_mouse_click(1);
    $w->handle_mouse_drag_update(3);
    $w->handle_mouse_drag_end();
    is($w->{drag_anchor}, undef, 'Drag anchor cleared on release');
    ok($w->has_selection(), 'Selection persists after release');
};

subtest 'drag_update with no drag_anchor is a no-op' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    $w->{cursor} = 2;
    $w->handle_mouse_drag_update(4);  # no drag_anchor set
    is($w->cursor(), 2, 'Cursor unchanged with no drag_anchor');
    ok(!$w->has_selection(), 'No selection created');
};

done_testing;
