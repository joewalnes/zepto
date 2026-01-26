#!/usr/bin/env perl
# Comprehensive tests for Zepto::InputParser
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Zepto::InputParser;

# ============================================================================
# Construction
# ============================================================================
subtest 'Construction' => sub {
    my $parser = Zepto::InputParser->new();
    ok($parser, 'Parser created');
};

# ============================================================================
# Regular characters
# ============================================================================
subtest 'Regular characters' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse('a');
    is(scalar @events, 1, 'One event');
    is($events[0]->{type}, 'char', 'Type is char');
    is($events[0]->{char}, 'a', 'Char is a');

    @events = $parser->parse('hello');
    is(scalar @events, 5, 'Five chars');
    is($events[0]->{char}, 'h', 'First char');
    is($events[4]->{char}, 'o', 'Last char');
};

subtest 'UTF-8 characters' => sub {
    my $parser = Zepto::InputParser->new();

    # Japanese (日 = E6 97 A5 in UTF-8)
    my @events = $parser->parse("\xE6\x97\xA5");
    is(scalar @events, 1, 'One UTF-8 char');
    # The decoded char should match (comparison in unicode)
    ok($events[0]->{char} eq "\x{65E5}", 'Japanese char decoded');

    # Emoji (4-byte UTF-8: 😀 = F0 9F 98 80)
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\xF0\x9F\x98\x80");
    is(scalar @events, 1, 'One emoji');
};

# ============================================================================
# Control characters
# ============================================================================
subtest 'Control characters' => sub {
    my $parser = Zepto::InputParser->new();

    # Tab
    my @events = $parser->parse("\t");
    is($events[0]->{type}, 'key', 'Tab is key');
    is($events[0]->{key}, 'tab', 'Tab key');

    # Enter (CR only - LF/Ctrl+J is handled separately as Ctrl+letter)
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\r");
    is($events[0]->{key}, 'enter', 'CR is enter');

    # Backspace
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x7f");  # DEL
    is($events[0]->{key}, 'backspace', 'DEL is backspace');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x08");  # BS
    is($events[0]->{key}, 'backspace', 'BS is backspace');
};

subtest 'Ctrl+letter' => sub {
    my $parser = Zepto::InputParser->new();

    # Ctrl+A = 0x01
    my @events = $parser->parse("\x01");
    is($events[0]->{type}, 'char', 'Ctrl+A type');
    is($events[0]->{char}, 'a', 'Ctrl+A char');
    ok(Zepto::InputParser::has_modifier($events[0], 'ctrl'), 'Has ctrl modifier');

    # Ctrl+C = 0x03
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x03");
    is($events[0]->{char}, 'c', 'Ctrl+C');
    ok(Zepto::InputParser::has_modifier($events[0], 'ctrl'), 'Ctrl+C has ctrl');

    # Ctrl+J = 0x0A (LF) - should be Ctrl+J, NOT Enter
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x0a");
    is($events[0]->{type}, 'char', 'Ctrl+J type is char (not key)');
    is($events[0]->{char}, 'j', 'Ctrl+J char is j');
    ok(Zepto::InputParser::has_modifier($events[0], 'ctrl'), 'Ctrl+J has ctrl');

    # Ctrl+Z = 0x1a
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1a");
    is($events[0]->{char}, 'z', 'Ctrl+Z');
};

subtest 'Ctrl+/ (0x1F)' => sub {
    my $parser = Zepto::InputParser->new();

    # Ctrl+/ sends 0x1F on most terminals
    my @events = $parser->parse("\x1f");
    is($events[0]->{type}, 'char', 'Ctrl+/ type is char');
    is($events[0]->{char}, '/', 'Ctrl+/ char is /');
    ok(Zepto::InputParser::has_modifier($events[0], 'ctrl'), 'Ctrl+/ has ctrl modifier');
};

# ============================================================================
# Arrow keys
# ============================================================================
subtest 'Arrow keys' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1b[A");
    is($events[0]->{type}, 'key', 'Up is key');
    is($events[0]->{key}, 'up', 'Up arrow');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[B");
    is($events[0]->{key}, 'down', 'Down arrow');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[C");
    is($events[0]->{key}, 'right', 'Right arrow');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[D");
    is($events[0]->{key}, 'left', 'Left arrow');
};

subtest 'Arrow keys with modifiers' => sub {
    my $parser = Zepto::InputParser->new();

    # Shift+Up: ESC [ 1 ; 2 A
    my @events = $parser->parse("\x1b[1;2A");
    is($events[0]->{key}, 'up', 'Shift+Up');
    ok(Zepto::InputParser::has_modifier($events[0], 'shift'), 'Has shift');

    # Ctrl+Right: ESC [ 1 ; 5 C
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[1;5C");
    is($events[0]->{key}, 'right', 'Ctrl+Right');
    ok(Zepto::InputParser::has_modifier($events[0], 'ctrl'), 'Has ctrl');

    # Alt+Down: ESC [ 1 ; 3 B
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[1;3B");
    is($events[0]->{key}, 'down', 'Alt+Down');
    ok(Zepto::InputParser::has_modifier($events[0], 'alt'), 'Has alt');

    # Ctrl+Shift+Left: ESC [ 1 ; 6 D
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[1;6D");
    is($events[0]->{key}, 'left', 'Ctrl+Shift+Left');
    ok(Zepto::InputParser::has_modifier($events[0], 'ctrl'), 'Has ctrl');
    ok(Zepto::InputParser::has_modifier($events[0], 'shift'), 'Has shift');
};

# ============================================================================
# Special keys
# ============================================================================
subtest 'Home/End' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1b[H");
    is($events[0]->{key}, 'home', 'Home (H)');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[F");
    is($events[0]->{key}, 'end', 'End (F)');

    # Alternate sequences
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[1~");
    is($events[0]->{key}, 'home', 'Home (1~)');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[4~");
    is($events[0]->{key}, 'end', 'End (4~)');
};

subtest 'Backtab (Shift+Tab)' => sub {
    my $parser = Zepto::InputParser->new();

    # Backtab: ESC [ Z
    my @events = $parser->parse("\x1b[Z");
    is(scalar @events, 1, 'One event');
    is($events[0]->{type}, 'key', 'Type is key');
    is($events[0]->{key}, 'tab', 'Key is tab');
    ok(Zepto::InputParser::has_modifier($events[0], 'shift'), 'Has shift modifier');
};

subtest 'Page Up/Down' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1b[5~");
    is($events[0]->{key}, 'pageup', 'Page Up');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[6~");
    is($events[0]->{key}, 'pagedown', 'Page Down');
};

subtest 'Insert/Delete' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1b[2~");
    is($events[0]->{key}, 'insert', 'Insert');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[3~");
    is($events[0]->{key}, 'delete', 'Delete');
};

# ============================================================================
# Function keys
# ============================================================================
subtest 'Function keys (CSI)' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1b[11~");
    is($events[0]->{key}, 'f1', 'F1');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[15~");
    is($events[0]->{key}, 'f5', 'F5');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[24~");
    is($events[0]->{key}, 'f12', 'F12');
};

subtest 'Function keys (SS3)' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1bOP");
    is($events[0]->{key}, 'f1', 'F1 (SS3)');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1bOQ");
    is($events[0]->{key}, 'f2', 'F2 (SS3)');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1bOR");
    is($events[0]->{key}, 'f3', 'F3 (SS3)');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1bOS");
    is($events[0]->{key}, 'f4', 'F4 (SS3)');
};

# ============================================================================
# Alt+key
# ============================================================================
subtest 'Alt+key' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1ba");
    is($events[0]->{type}, 'char', 'Alt+a type');
    is($events[0]->{char}, 'a', 'Alt+a char');
    ok(Zepto::InputParser::has_modifier($events[0], 'alt'), 'Has alt');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1bx");
    is($events[0]->{char}, 'x', 'Alt+x');
    ok(Zepto::InputParser::has_modifier($events[0], 'alt'), 'Alt+x has alt');
};

# ============================================================================
# Escape key
# ============================================================================
subtest 'Escape key' => sub {
    my $parser = Zepto::InputParser->new();

    # ESC alone needs flush
    my @events = $parser->parse("\x1b");
    is(scalar @events, 0, 'ESC alone returns no events (needs more input)');

    my $event = $parser->flush_pending();
    ok($event, 'Flush returns event');
    is($event->{key}, 'escape', 'Escape key');
};

# ============================================================================
# Mouse events (SGR format)
# ============================================================================
subtest 'Mouse press (SGR)' => sub {
    my $parser = Zepto::InputParser->new();

    # Left click at (10, 5): ESC [ < 0 ; 10 ; 5 M
    my @events = $parser->parse("\x1b[<0;10;5M");
    is($events[0]->{type}, 'mouse', 'Mouse type');
    is($events[0]->{action}, 'press', 'Press action');
    is($events[0]->{button}, 0, 'Left button');
    is($events[0]->{x}, 10, 'X coord');
    is($events[0]->{y}, 5, 'Y coord');
};

subtest 'Mouse release (SGR)' => sub {
    my $parser = Zepto::InputParser->new();

    # Release at (10, 5): ESC [ < 0 ; 10 ; 5 m (lowercase m)
    my @events = $parser->parse("\x1b[<0;10;5m");
    is($events[0]->{action}, 'release', 'Release action');
};

subtest 'Mouse with modifiers' => sub {
    my $parser = Zepto::InputParser->new();

    # Shift+click: button 0 + 4 = 4
    my @events = $parser->parse("\x1b[<4;10;5M");
    is($events[0]->{action}, 'press', 'Press');
    ok(Zepto::InputParser::has_modifier($events[0], 'shift'), 'Has shift');

    # Ctrl+click: button 0 + 16 = 16
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[<16;10;5M");
    ok(Zepto::InputParser::has_modifier($events[0], 'ctrl'), 'Has ctrl');
};

subtest 'Mouse scroll' => sub {
    my $parser = Zepto::InputParser->new();

    # Scroll up: button 64
    my @events = $parser->parse("\x1b[<64;10;5M");
    is($events[0]->{action}, 'scroll', 'Scroll action');
    is($events[0]->{button}, 'up', 'Scroll up');

    # Scroll down: button 65
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[<65;10;5M");
    is($events[0]->{button}, 'down', 'Scroll down');
};

subtest 'Mouse drag' => sub {
    my $parser = Zepto::InputParser->new();

    # Drag: button + 32
    my @events = $parser->parse("\x1b[<32;15;10M");
    is($events[0]->{action}, 'drag', 'Drag action');
};

subtest 'Mouse motion without button is ignored' => sub {
    my $parser = Zepto::InputParser->new();

    # Motion without button: btn=3 + motion=32 = 35
    # This is pure mouse movement, not a drag
    my @events = $parser->parse("\x1b[<35;15;10M");
    is(scalar @events, 0, 'Motion without button produces no event');
};

# ============================================================================
# Mixed input
# ============================================================================
subtest 'Mixed input' => sub {
    my $parser = Zepto::InputParser->new();

    # "hi" + up arrow + "x"
    my @events = $parser->parse("hi\x1b[Ax");
    is(scalar @events, 4, 'Four events');
    is($events[0]->{char}, 'h', 'First char');
    is($events[1]->{char}, 'i', 'Second char');
    is($events[2]->{key}, 'up', 'Arrow key');
    is($events[3]->{char}, 'x', 'Last char');
};

# ============================================================================
# Incremental parsing
# ============================================================================
subtest 'Incremental parsing' => sub {
    my $parser = Zepto::InputParser->new();

    # Send escape sequence in parts
    my @events = $parser->parse("\x1b");
    is(scalar @events, 0, 'ESC alone');

    @events = $parser->parse("[");
    is(scalar @events, 0, 'ESC[ incomplete');

    @events = $parser->parse("A");
    is(scalar @events, 1, 'Complete sequence');
    is($events[0]->{key}, 'up', 'Up arrow');
};

# ============================================================================
# Edge cases
# ============================================================================
subtest 'Empty input' => sub {
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse('');
    is(scalar @events, 0, 'Empty input');

    @events = $parser->parse(undef);
    is(scalar @events, 0, 'Undef input');
};

subtest 'describe_event' => sub {
    my $char_evt = { type => 'char', char => 'a', modifiers => [] };
    like(Zepto::InputParser::describe_event($char_evt), qr/char:'a'/, 'Describe char');

    my $key_evt = { type => 'key', key => 'up', modifiers => ['ctrl'] };
    like(Zepto::InputParser::describe_event($key_evt), qr/key:up\+ctrl/, 'Describe key with mod');

    my $mouse_evt = { type => 'mouse', action => 'press', x => 10, y => 5, modifiers => [] };
    like(Zepto::InputParser::describe_event($mouse_evt), qr/mouse:press\@10,5/, 'Describe mouse');
};

done_testing();
