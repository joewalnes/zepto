package Zepto::InputParser;
# InputParser: Convert raw terminal input bytes to semantic events
# Handles escape sequences, special keys, mouse events, and UTF-8

use strict;
use warnings;
use utf8;

# Event types
use constant {
    EVT_CHAR   => 'char',      # Regular character
    EVT_KEY    => 'key',       # Special key (arrow, function, etc.)
    EVT_MOUSE  => 'mouse',     # Mouse event
    EVT_RESIZE => 'resize',    # Terminal resize (from signal, not parser)
    EVT_NONE   => 'none',      # No event / incomplete sequence
};

# Key constants
use constant {
    KEY_UP        => 'up',
    KEY_DOWN      => 'down',
    KEY_LEFT      => 'left',
    KEY_RIGHT     => 'right',
    KEY_HOME      => 'home',
    KEY_END       => 'end',
    KEY_PAGEUP    => 'pageup',
    KEY_PAGEDOWN  => 'pagedown',
    KEY_INSERT    => 'insert',
    KEY_DELETE    => 'delete',
    KEY_BACKSPACE => 'backspace',
    KEY_TAB       => 'tab',
    KEY_ENTER     => 'enter',
    KEY_ESCAPE    => 'escape',
    KEY_F1        => 'f1',
    KEY_F2        => 'f2',
    KEY_F3        => 'f3',
    KEY_F4        => 'f4',
    KEY_F5        => 'f5',
    KEY_F6        => 'f6',
    KEY_F7        => 'f7',
    KEY_F8        => 'f8',
    KEY_F9        => 'f9',
    KEY_F10       => 'f10',
    KEY_F11       => 'f11',
    KEY_F12       => 'f12',
};

# Mouse actions
use constant {
    MOUSE_PRESS   => 'press',
    MOUSE_RELEASE => 'release',
    MOUSE_DRAG    => 'drag',
    MOUSE_SCROLL  => 'scroll',
};

sub new {
    my ($class) = @_;

    my $self = bless {
        buffer => '',          # Accumulated input bytes
        _pending_esc => 0,     # Waiting to see if ESC is standalone
    }, $class;

    return $self;
}

# Feed bytes into the parser, return list of events
sub parse {
    my ($self, $bytes) = @_;
    return () unless defined $bytes && length $bytes;

    $self->{buffer} .= $bytes;
    my @events;

    while (length $self->{buffer}) {
        my $event = $self->_parse_one();
        last if !$event || $event->{type} eq EVT_NONE;
        push @events, $event;
    }

    return @events;
}

# Check if there's a pending escape that might need to be flushed
# Call this after a timeout if no more input arrives
sub flush_pending {
    my ($self) = @_;

    if ($self->{buffer} eq "\x1b") {
        $self->{buffer} = '';
        return { type => EVT_KEY, key => KEY_ESCAPE, modifiers => [] };
    }
    return undef;
}

# Parse one event from the buffer
sub _parse_one {
    my ($self) = @_;

    return undef unless length $self->{buffer};

    my $first = substr($self->{buffer}, 0, 1);
    my $ord = ord($first);

    # Escape sequence
    if ($first eq "\x1b") {
        return $self->_parse_escape();
    }

    # Control characters
    if ($ord < 32) {
        return $self->_parse_control($ord);
    }

    # DEL (backspace on some terminals)
    if ($ord == 127) {
        substr($self->{buffer}, 0, 1, '');
        return { type => EVT_KEY, key => KEY_BACKSPACE, modifiers => [] };
    }

    # Regular character (possibly UTF-8)
    return $self->_parse_char();
}

# Parse escape sequence
sub _parse_escape {
    my ($self) = @_;

    my $buf = $self->{buffer};
    my $len = length($buf);

    # Just ESC alone - might be standalone or start of sequence
    if ($len == 1) {
        return { type => EVT_NONE };  # Need more input
    }

    my $second = substr($buf, 1, 1);

    # CSI sequence: ESC [
    if ($second eq '[') {
        return $self->_parse_csi();
    }

    # SS3 sequence: ESC O (some function keys)
    if ($second eq 'O') {
        return $self->_parse_ss3();
    }

    # Alt+key: ESC followed by regular key
    if (ord($second) >= 32 && ord($second) < 127) {
        substr($self->{buffer}, 0, 2, '');
        return $self->_make_char_event($second, ['alt']);
    }

    # Unknown escape sequence - just return ESC
    substr($self->{buffer}, 0, 1, '');
    return { type => EVT_KEY, key => KEY_ESCAPE, modifiers => [] };
}

# Parse CSI sequence (ESC [ ...)
sub _parse_csi {
    my ($self) = @_;

    my $buf = $self->{buffer};

    # Look for the final byte (ASCII 64-126)
    my $i = 2;
    while ($i < length($buf)) {
        my $c = ord(substr($buf, $i, 1));
        if ($c >= 64 && $c <= 126) {
            # Found terminator
            my $seq = substr($buf, 0, $i + 1);
            substr($self->{buffer}, 0, $i + 1, '');
            return $self->_decode_csi($seq);
        }
        $i++;
        # Sanity limit
        if ($i > 32) {
            # Invalid sequence, discard
            substr($self->{buffer}, 0, 2, '');
            return { type => EVT_NONE };
        }
    }

    # Incomplete sequence
    return { type => EVT_NONE };
}

# Decode a complete CSI sequence
sub _decode_csi {
    my ($self, $seq) = @_;

    # Remove ESC [
    $seq = substr($seq, 2);

    my $final = substr($seq, -1);
    my $params = substr($seq, 0, -1);

    # Parse modifiers from parameter (format: code;modifier)
    my @parts = split /;/, $params;
    my $modifiers = [];

    if (@parts >= 2) {
        my $mod = $parts[-1];
        $modifiers = $self->_decode_modifiers($mod);
    }

    # Mouse events (SGR format): <button;x;y M/m
    if ($params =~ /^<(\d+);(\d+);(\d+)$/ && ($final eq 'M' || $final eq 'm')) {
        return $self->_decode_sgr_mouse($1, $2, $3, $final);
    }

    # Mouse events (basic format)
    if ($final eq 'M' && length($params) == 0 && length($self->{buffer}) >= 0) {
        # Need 3 more bytes for basic mouse
        # Actually buffer was already consumed... handle differently
    }

    # Arrow keys
    if ($final eq 'A') { return $self->_make_key_event(KEY_UP, $modifiers); }
    if ($final eq 'B') { return $self->_make_key_event(KEY_DOWN, $modifiers); }
    if ($final eq 'C') { return $self->_make_key_event(KEY_RIGHT, $modifiers); }
    if ($final eq 'D') { return $self->_make_key_event(KEY_LEFT, $modifiers); }

    # Home/End
    if ($final eq 'H') { return $self->_make_key_event(KEY_HOME, $modifiers); }
    if ($final eq 'F') { return $self->_make_key_event(KEY_END, $modifiers); }

    # Backtab (Shift+Tab)
    if ($final eq 'Z') { return $self->_make_key_event(KEY_TAB, ['shift']); }

    # Home/End (alternate)
    if ($final eq '~') {
        my $code = $parts[0] // '';
        if ($code eq '1') { return $self->_make_key_event(KEY_HOME, $modifiers); }
        if ($code eq '2') { return $self->_make_key_event(KEY_INSERT, $modifiers); }
        if ($code eq '3') { return $self->_make_key_event(KEY_DELETE, $modifiers); }
        if ($code eq '4') { return $self->_make_key_event(KEY_END, $modifiers); }
        if ($code eq '5') { return $self->_make_key_event(KEY_PAGEUP, $modifiers); }
        if ($code eq '6') { return $self->_make_key_event(KEY_PAGEDOWN, $modifiers); }
        if ($code eq '7') { return $self->_make_key_event(KEY_HOME, $modifiers); }
        if ($code eq '8') { return $self->_make_key_event(KEY_END, $modifiers); }
        # Function keys
        if ($code eq '11') { return $self->_make_key_event(KEY_F1, $modifiers); }
        if ($code eq '12') { return $self->_make_key_event(KEY_F2, $modifiers); }
        if ($code eq '13') { return $self->_make_key_event(KEY_F3, $modifiers); }
        if ($code eq '14') { return $self->_make_key_event(KEY_F4, $modifiers); }
        if ($code eq '15') { return $self->_make_key_event(KEY_F5, $modifiers); }
        if ($code eq '17') { return $self->_make_key_event(KEY_F6, $modifiers); }
        if ($code eq '18') { return $self->_make_key_event(KEY_F7, $modifiers); }
        if ($code eq '19') { return $self->_make_key_event(KEY_F8, $modifiers); }
        if ($code eq '20') { return $self->_make_key_event(KEY_F9, $modifiers); }
        if ($code eq '21') { return $self->_make_key_event(KEY_F10, $modifiers); }
        if ($code eq '23') { return $self->_make_key_event(KEY_F11, $modifiers); }
        if ($code eq '24') { return $self->_make_key_event(KEY_F12, $modifiers); }
    }

    # CSI u (fixterms/kitty keyboard protocol): ESC [ codepoint ; modifiers u
    if ($final eq 'u' && @parts >= 1) {
        my $codepoint = $parts[0];
        if ($codepoint >= 32 && $codepoint < 127) {
            return $self->_make_char_event(chr($codepoint), $modifiers);
        }
    }

    # Unknown CSI sequence
    return { type => EVT_NONE };
}

# Parse SS3 sequence (ESC O ...)
sub _parse_ss3 {
    my ($self) = @_;

    if (length($self->{buffer}) < 3) {
        return { type => EVT_NONE };  # Need more input
    }

    my $final = substr($self->{buffer}, 2, 1);
    substr($self->{buffer}, 0, 3, '');

    # Arrow keys (some terminals)
    if ($final eq 'A') { return $self->_make_key_event(KEY_UP, []); }
    if ($final eq 'B') { return $self->_make_key_event(KEY_DOWN, []); }
    if ($final eq 'C') { return $self->_make_key_event(KEY_RIGHT, []); }
    if ($final eq 'D') { return $self->_make_key_event(KEY_LEFT, []); }

    # Home/End (some terminals)
    if ($final eq 'H') { return $self->_make_key_event(KEY_HOME, []); }
    if ($final eq 'F') { return $self->_make_key_event(KEY_END, []); }

    # Function keys F1-F4
    if ($final eq 'P') { return $self->_make_key_event(KEY_F1, []); }
    if ($final eq 'Q') { return $self->_make_key_event(KEY_F2, []); }
    if ($final eq 'R') { return $self->_make_key_event(KEY_F3, []); }
    if ($final eq 'S') { return $self->_make_key_event(KEY_F4, []); }

    return { type => EVT_NONE };
}

# Decode SGR mouse event
sub _decode_sgr_mouse {
    my ($self, $button, $x, $y, $final) = @_;

    # Button encoding:
    # 0 = left, 1 = middle, 2 = right, 3 = release/none
    # +4 = shift, +8 = alt, +16 = ctrl
    # +32 = motion (drag or move)
    # +64 = scroll

    my $btn = $button & 3;
    my $motion = $button & 32;
    my $scroll = $button & 64;

    my $modifiers = [];
    push @$modifiers, 'shift' if $button & 4;
    push @$modifiers, 'alt' if $button & 8;
    push @$modifiers, 'ctrl' if $button & 16;

    my $action;
    if ($scroll) {
        $action = MOUSE_SCROLL;
        $btn = ($btn == 0) ? 'up' : 'down';
    }
    elsif ($motion) {
        # Motion with btn == 3 means mouse movement without any button held
        # This is not a drag, just movement - ignore it
        if ($btn == 3) {
            return { type => EVT_NONE };
        }
        $action = MOUSE_DRAG;
    }
    elsif ($final eq 'M') {
        $action = MOUSE_PRESS;
    }
    else {
        $action = MOUSE_RELEASE;
    }

    return {
        type      => EVT_MOUSE,
        action    => $action,
        button    => $btn,
        x         => $x,       # 1-indexed
        y         => $y,       # 1-indexed
        modifiers => $modifiers,
    };
}

# Parse control character
sub _parse_control {
    my ($self, $ord) = @_;

    substr($self->{buffer}, 0, 1, '');

    # Special control characters
    if ($ord == 9)  { return { type => EVT_KEY, key => KEY_TAB, modifiers => [] }; }
    if ($ord == 13) { return { type => EVT_KEY, key => KEY_ENTER, modifiers => [] }; }  # CR only
    if ($ord == 8)  { return { type => EVT_KEY, key => KEY_BACKSPACE, modifiers => [] }; }

    # Ctrl+Space sends NUL (0x00)
    if ($ord == 0) {
        return $self->_make_char_event(' ', ['ctrl']);
    }

    # Ctrl+letter (1-26 = Ctrl+A through Ctrl+Z)
    if ($ord >= 1 && $ord <= 26) {
        my $char = chr(ord('a') + $ord - 1);
        return $self->_make_char_event($char, ['ctrl']);
    }

    # Ctrl+/ sends 0x1F on most terminals
    if ($ord == 0x1F) {
        return $self->_make_char_event('/', ['ctrl']);
    }

    # Other control chars - return as-is
    return { type => EVT_CHAR, char => chr($ord), modifiers => [] };
}

# Parse regular character (possibly UTF-8)
sub _parse_char {
    my ($self) = @_;

    my $first = ord(substr($self->{buffer}, 0, 1));
    my $bytes_needed = 1;

    # UTF-8 decoding
    if (($first & 0xE0) == 0xC0) { $bytes_needed = 2; }
    elsif (($first & 0xF0) == 0xE0) { $bytes_needed = 3; }
    elsif (($first & 0xF8) == 0xF0) { $bytes_needed = 4; }

    if (length($self->{buffer}) < $bytes_needed) {
        return { type => EVT_NONE };  # Need more bytes
    }

    my $char = substr($self->{buffer}, 0, $bytes_needed, '');

    # UTF-8 is handled by Perl's native string handling
    # Just ensure the string flag is set properly
    utf8::decode($char) if $bytes_needed > 1;

    return { type => EVT_CHAR, char => $char, modifiers => [] };
}

# Decode modifier number to list
sub _decode_modifiers {
    my ($self, $mod) = @_;

    $mod = ($mod // 1) - 1;  # Subtract 1 (1 = no modifier)
    my @mods;

    push @mods, 'shift' if $mod & 1;
    push @mods, 'alt'   if $mod & 2;
    push @mods, 'ctrl'  if $mod & 4;

    return \@mods;
}

# Helper to make key event
sub _make_key_event {
    my ($self, $key, $modifiers) = @_;
    return {
        type      => EVT_KEY,
        key       => $key,
        modifiers => $modifiers // [],
    };
}

# Helper to make char event with modifiers
sub _make_char_event {
    my ($self, $char, $modifiers) = @_;
    return {
        type      => EVT_CHAR,
        char      => $char,
        modifiers => $modifiers // [],
    };
}

# Utility: check if event has modifier
sub has_modifier {
    my ($event, $mod) = @_;
    return 0 unless $event && $event->{modifiers};
    return grep { $_ eq $mod } @{$event->{modifiers}};
}

# Utility: describe event for debugging
sub describe_event {
    my ($event) = @_;
    return 'undef' unless $event;

    my $desc = $event->{type};

    if ($event->{type} eq EVT_CHAR) {
        $desc .= ":'" . $event->{char} . "'";
    }
    elsif ($event->{type} eq EVT_KEY) {
        $desc .= ':' . $event->{key};
    }
    elsif ($event->{type} eq EVT_MOUSE) {
        $desc .= ':' . $event->{action} . '@' . $event->{x} . ',' . $event->{y};
    }

    if ($event->{modifiers} && @{$event->{modifiers}}) {
        $desc .= '+' . join('+', @{$event->{modifiers}});
    }

    return $desc;
}

1;
