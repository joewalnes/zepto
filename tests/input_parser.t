#!/usr/bin/env perl
# Comprehensive tests for Zepto::InputParser
use strict;
use warnings;
use utf8;
use Test::More;
use Time::HiRes qw(sleep);
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

subtest 'Ctrl+Space (0x00 NUL)' => sub {
    my $parser = Zepto::InputParser->new();

    # Ctrl+Space sends NUL (0x00) on most terminals
    my @events = $parser->parse("\x00");
    is(scalar @events, 1, 'One event from Ctrl+Space');
    is($events[0]->{type}, 'char', 'Ctrl+Space type is char');
    is($events[0]->{char}, ' ', 'Ctrl+Space char is space');
    ok(Zepto::InputParser::has_modifier($events[0], 'ctrl'), 'Ctrl+Space has ctrl modifier');
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

subtest 'Bracketed paste sequences' => sub {
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1b[200~");
    is(scalar @events, 1, 'paste_start parsed');
    is($events[0]->{type}, 'key', 'paste_start is key event');
    is($events[0]->{key}, 'paste_start', 'paste_start key value');

    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[201~");
    is(scalar @events, 1, 'paste_end parsed');
    is($events[0]->{key}, 'paste_end', 'paste_end key value');

    # Full paste sequence: start + content + end
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[200~hello\x1b[201~");
    is($events[0]->{key}, 'paste_start', 'paste sequence starts');
    is($events[-1]->{key}, 'paste_end', 'paste sequence ends');
    ok(scalar @events > 2, 'paste content between delimiters');
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
# ESC disambiguation across separate parse() calls (regression: bugs.md P2
# "Escape immediately followed by a burst keystroke send can drop or
# corrupt the next character(s)" / QA-REG-170)
#
# A real Alt-chord (ESC + printable byte) is written by the terminal as a
# single atomic write and always arrives together in one parse() call — see
# the "Alt+key" subtest above, which feeds both bytes in a single string.
# But when a lone ESC is fed in one parse() call and the continuation byte
# arrives in a genuinely LATER, separate parse() call (as happens when the
# two bytes come from separate underlying reads), the parser must not wait
# indefinitely (up to the ~0.5s outer idle-read timeout in Editor.pm) to
# decide the ESC was standalone — otherwise a byte in the 32-126 range
# (like a space) arriving after a human-perceptible pause gets fused into
# "Alt+<byte>" instead of being a separate Escape + character.
# ============================================================================
subtest 'ESC resolves as standalone once a continuation byte arrives too late' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1b");
    is(scalar @events, 0, 'lone ESC alone: no events yet (still waiting)');

    # Wait past ESC_DISAMBIGUATION_TIMEOUT (30ms) before the next byte
    # arrives in a separate parse() call.
    sleep(0.06);

    @events = $parser->parse(' ');
    is(scalar @events, 2, 'two separate events: stale ESC resolved, then the new byte parsed fresh');
    is($events[0]->{type}, 'key', 'first event is a key event');
    is($events[0]->{key}, 'escape', 'first event is standalone Escape');
    is($events[1]->{type}, 'char', 'second event is a plain char');
    is($events[1]->{char}, ' ', 'second event is the space, unmodified');
    ok(!Zepto::InputParser::has_modifier($events[1], 'alt'),
        'space is NOT fused into Alt+Space');
};

subtest 'ESC + continuation byte arriving quickly (same "burst") still forms an Alt-chord' => sub {
    my $parser = Zepto::InputParser->new();

    my @events = $parser->parse("\x1b");
    is(scalar @events, 0, 'lone ESC alone: no events yet (still waiting)');

    # No meaningful delay — matches how a real terminal delivers an
    # atomic Alt-chord write, even if split across two parse() calls by
    # the read loop (e.g. very fast successive reads with no real gap).
    @events = $parser->parse(' ');
    is(scalar @events, 1, 'single fused event, not resolved as standalone Escape');
    is($events[0]->{type}, 'char', 'event is a char');
    is($events[0]->{char}, ' ', 'char is space');
    ok(Zepto::InputParser::has_modifier($events[0], 'alt'), 'Alt+Space when bytes arrive with no real gap');
};

subtest 'ESC disambiguation does not affect genuine same-call Alt-chords' => sub {
    # Sanity check this fix didn't regress the base case: both bytes fed
    # in a single parse() call (how every real terminal actually sends
    # an Alt-chord) must still resolve as one Alt+key event regardless of
    # ESC_DISAMBIGUATION_TIMEOUT.
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1bz");
    is(scalar @events, 1, 'single event for same-call ESC+z');
    is($events[0]->{char}, 'z', 'char is z');
    ok(Zepto::InputParser::has_modifier($events[0], 'alt'), 'has alt modifier');
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

subtest 'Mouse motion without button emits move event' => sub {
    my $parser = Zepto::InputParser->new();

    # Motion without button: btn=3 + motion=32 = 35
    # This is pure mouse movement — emitted as 'move' for hover effects
    my @events = $parser->parse("\x1b[<35;15;10M");
    is(scalar @events, 1, 'Motion without button produces one event');
    is($events[0]->{action}, 'move', 'Action is move');
    is($events[0]->{x}, 15, 'Move x position');
    is($events[0]->{y}, 10, 'Move y position');
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

# ============================================================================
# Unknown sequences must not stall the event queue (QA-REG-102)
# ============================================================================
# Regression: a complete-but-unrecognized sequence must be discarded and
# parsing must continue in the same batch. Previously parse() stopped at the
# first EVT_NONE even when bytes had been consumed, so events behind junk sat
# in the buffer until the NEXT input arrived — keys lagged one event behind.
subtest 'Unknown CSI does not stall following events' => sub {
    # Focus-in (ESC [ I) is not handled — must be discarded, Up must fire
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1b[I\x1b[A");
    is(scalar @events, 1, 'One event from unknown-CSI + Up batch');
    is($events[0]->{type}, 'key', 'Event is a key');
    is($events[0]->{key}, 'up', 'Up arrow survived the unknown CSI');
    is(length($parser->{buffer}), 0, 'No bytes left stuck in buffer');

    # Unknown CSI followed by a typed character
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[Ox");
    is(scalar @events, 1, 'One event from unknown-CSI + char batch');
    is($events[0]->{type}, 'char', 'Char event');
    is($events[0]->{char}, 'x', 'Typed char survived the unknown CSI');

    # Multiple unknown sequences interleaved with real events
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[I" . "a" . "\x1b[O" . "\x1b[B");
    is(scalar @events, 2, 'Two events from mixed batch');
    is($events[0]->{char}, 'a', 'Char parsed');
    is($events[1]->{key}, 'down', 'Down arrow parsed');
};

subtest 'Basic-format (non-SGR) mouse report is not decoded — treated as unknown CSI' => sub {
    # QA-REG-145: Zepto only ever enables SGR mouse mode (Terminal.pm sends
    # "\x1b[?1003h\x1b[?1006h" — no bare "?1000h"), so a real terminal never
    # emits the legacy 3-byte "ESC [ M Cb Cx Cy" report. There used to be an
    # empty, tautological ("length >= 0") if-block here that looked like an
    # abandoned attempt to handle that format. This test proves it was
    # already fully inert *before* removal: "ESC [ M" terminates as its own
    # CSI sequence (M is a valid CSI final byte), decodes as an unknown CSI
    # (EVT_NONE, discarded), and the three legacy data bytes that would
    # follow are parsed independently as plain characters — exactly as they
    # are now that the dead branch is gone.
    my $parser = Zepto::InputParser->new();
    # Cb=32 (button 0, no modifiers), Cx=33 (col 1), Cy=34 (row 2)
    my @events = $parser->parse("\x1b[M" . chr(32) . chr(33) . chr(34));
    is(scalar @events, 3, 'Unknown CSI (discarded) plus three literal char events');
    is($events[0]->{type}, 'char', 'First data byte parsed as a char, not a mouse event');
    is($events[0]->{char}, chr(32), 'First data byte value');
    is($events[1]->{char}, chr(33), 'Second data byte value');
    is($events[2]->{char}, chr(34), 'Third data byte value');
    is(length($parser->{buffer}), 0, 'No bytes left stuck in buffer');
};

subtest 'Unknown SS3 does not stall following events' => sub {
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1bOZ" . "q");
    is(scalar @events, 1, 'One event from unknown-SS3 + char batch');
    is($events[0]->{char}, 'q', 'Char survived the unknown SS3');
};

subtest 'Out-of-range CSI-u does not stall following events' => sub {
    # CSI u with codepoint outside 32..126 (e.g. Enter = 13) is unhandled
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1b[13;5u" . "a");
    is(scalar @events, 1, 'One event from CSI-u + char batch');
    is($events[0]->{char}, 'a', 'Char survived the unhandled CSI-u');
};

subtest 'Incomplete sequences still wait for more bytes' => sub {
    # A truly incomplete sequence must NOT be discarded — it completes
    # when the rest arrives (split across reads)
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1b[");
    is(scalar @events, 0, 'Incomplete CSI produces no events');
    @events = $parser->parse("A");
    is(scalar @events, 1, 'Completed on next read');
    is($events[0]->{key}, 'up', 'Split CSI decoded as Up');

    # Split SGR mouse sequence
    $parser = Zepto::InputParser->new();
    @events = $parser->parse("\x1b[<35;10");
    is(scalar @events, 0, 'Partial SGR mouse produces no events');
    @events = $parser->parse(";5M");
    is(scalar @events, 1, 'SGR mouse completed on next read');
    is($events[0]->{type}, 'mouse', 'Mouse event');
    is($events[0]->{action}, 'move', 'Motion decoded');
};

# ============================================================================
# OSC sequences (QA-REG-138 / QA-THM auto-theme detection support)
# ============================================================================
# Regression: "ESC ]" previously fell into the generic Alt+key branch,
# producing an Alt+']' char event immediately followed by every byte of
# the OSC payload as further bogus char events — a terminal OSC response
# (e.g. a background-color query reply used for Linux theme auto-detect)
# would have spammed garbage keystrokes into whatever was focused.
subtest 'OSC sequence (BEL-terminated) is consumed, not misparsed' => sub {
    my $parser = Zepto::InputParser->new();
    # OSC 11 background-color response, BEL-terminated, followed by a real
    # keystroke that must survive intact.
    my @events = $parser->parse("\x1b]11;rgb:1a1a/1a1a/2626\x07" . "x");
    is(scalar @events, 1, 'Only the real keystroke produced an event');
    is($events[0]->{type}, 'char', 'Char event');
    is($events[0]->{char}, 'x', 'Char survived the OSC sequence intact');
    is(length($parser->{buffer}), 0, 'No bytes left stuck in buffer');
};

subtest 'OSC sequence (ST-terminated) is consumed, not misparsed' => sub {
    my $parser = Zepto::InputParser->new();
    # ST = ESC \
    my @events = $parser->parse("\x1b]11;rgb:ffff/ffff/ffff\x1b\\" . "y");
    is(scalar @events, 1, 'Only the real keystroke produced an event');
    is($events[0]->{char}, 'y', 'Char survived the ST-terminated OSC sequence');
};

subtest 'OSC sequence does not corrupt following keystrokes character-by-character' => sub {
    # This is the actual failure mode of the pre-fix bug: without OSC
    # recognition, "]" is consumed as Alt+']', and then "1", "1", ";", etc.
    # are each parsed as their own regular char events.
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1b]11;rgb:0000/0000/0000\x07" . "ab");
    is(scalar @events, 2, 'Exactly the two real keystrokes, nothing from the OSC body');
    is($events[0]->{char}, 'a', 'First real char');
    is($events[1]->{char}, 'b', 'Second real char');
};

subtest 'Incomplete OSC sequence waits for its terminator' => sub {
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1b]11;rgb:1a1a");
    is(scalar @events, 0, 'No event yet, terminator not seen');
    ok(length($parser->{buffer}) > 0, 'Bytes retained, waiting for terminator');

    @events = $parser->parse("/1a1a/2626\x07" . "z");
    is(scalar @events, 1, 'Completes once the terminator arrives');
    is($events[0]->{char}, 'z', 'Real char after the split OSC sequence');
};

subtest 'Runaway (unterminated) OSC body is eventually discarded' => sub {
    my $parser = Zepto::InputParser->new();
    # Well past OSC_MAX_LEN with no BEL/ST anywhere in this read — must be
    # discarded rather than wedging the parser (or the whole buffer)
    # forever. A byte string this size with no terminator can't be
    # distinguished from real keystrokes concatenated into the same read,
    # so the whole blob is dropped — the important guarantee is that the
    # parser recovers cleanly afterward.
    my @events = $parser->parse("\x1b]" . ('9' x 600));
    is(scalar @events, 0, 'Runaway OSC body produces no garbage char events');
    is(length($parser->{buffer}), 0, 'Buffer fully drained, not wedged');

    # A real keystroke arriving in a SEPARATE read afterward (the
    # realistic case — the terminal never sent a terminator, and the user
    # then typed something) must parse normally.
    @events = $parser->parse("z");
    is(scalar @events, 1, 'Parser recovered for the next real read');
    is($events[0]->{char}, 'z', 'Real char after runaway OSC body recovers cleanly');
};

subtest 'Lone "ESC ]" with nothing following is Alt+\']\' on flush' => sub {
    # A human pressing Alt+] produces exactly "ESC ]" and then nothing
    # else — indistinguishable from the start of an OSC sequence until a
    # read timeout proves no terminator is coming. This must still work
    # as Alt+']', matching the existing bare-ESC flush behavior.
    my $parser = Zepto::InputParser->new();
    my @events = $parser->parse("\x1b]");
    is(scalar @events, 0, 'No event yet, could still be an OSC sequence starting');

    my $event = $parser->flush_pending();
    ok($event, 'Flush returns an event');
    is($event->{type}, 'char', 'Alt+] is a char event');
    is($event->{char}, ']', 'Char is ]');
    ok(Zepto::InputParser::has_modifier($event, 'alt'), 'Has alt modifier');
    is(length($parser->{buffer}), 0, 'Buffer cleared after flush');
};

done_testing();
