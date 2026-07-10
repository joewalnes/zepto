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

# =============================================================================
# Control character hardening (QA-REG regression: raw ESC/control bytes must
# never render inside an input field — see bugs.md CI add-on, Phase 2)
# =============================================================================

subtest 'raw control char in a char event is rejected, not inserted' => sub {
    my $w = Zepto::InputWidget->new(value => 'hello');
    # This should never happen via the real InputParser (ESC and other C0
    # controls are routed as 'key' events, not 'char' events — see
    # InputParser::_parse_one), but the widget must not trust that
    # invariant blindly: a literal ESC byte handed to it as a 'char' event
    # must be rejected rather than rendered.
    my $handled = $w->handle_event(char_event("\x1b"));
    is($w->value(), 'hello', 'Value unchanged — ESC byte not inserted');
    ok(!$handled, 'handle_event reports the control char was not handled');
};

subtest 'other C0 control chars and DEL are rejected as char events' => sub {
    for my $byte (0x00, 0x01, 0x07, 0x0b, 0x1f, 0x7f) {
        my $w = Zepto::InputWidget->new(value => 'x');
        $w->handle_event(char_event(chr($byte)));
        is($w->value(), 'x', sprintf('Control byte 0x%02x not inserted', $byte));
    }
};

subtest 'tab is a control char and is also rejected (single-line widget)' => sub {
    my $w = Zepto::InputWidget->new(value => 'ab');
    $w->handle_event(char_event("\t"));
    is($w->value(), 'ab', 'Tab not inserted into single-line widget');
};

subtest 'pasted clipboard text is sanitized of control chars' => sub {
    my $w = Zepto::InputWidget->new(value => '');
    my $clipboard = "hello\x1bworld\nmore";
    $w->handle_event(char_event('v', 'ctrl'), \$clipboard);
    is($w->value(), 'helloworldmore', 'Control chars stripped from pasted text');
};

subtest 'normal printable and unicode chars still insert fine' => sub {
    my $w = Zepto::InputWidget->new(value => '');
    $w->handle_event(char_event('a'));
    $w->handle_event(char_event(' '));
    $w->handle_event(char_event('~'));
    $w->handle_event(char_event("\x{00e9}"));  # e-acute, printable non-ASCII
    is($w->value(), "a ~\x{00e9}", 'Printable and unicode chars unaffected by hardening');
};

done_testing;
