package Zepto::Terminal;
# =============================================================================
# Terminal: Low-level terminal I/O wrapper
# =============================================================================
#
# Handles:
#   - Raw mode (disable line buffering, echo, etc.)
#   - Terminal size detection
#   - Mouse enable/disable
#   - Non-blocking input
#   - Output buffering for smooth rendering
#
# Uses POSIX termios for raw mode. Should work on Linux, macOS, BSD.
# =============================================================================

use strict;
use warnings;
use POSIX qw(TCSANOW);
use IO::Select;

# Escape sequences for terminal control
use constant {
    ESC => "\x1b",

    # Cursor
    HIDE_CURSOR    => "\x1b[?25l",
    SHOW_CURSOR    => "\x1b[?25h",
    CURSOR_HOME    => "\x1b[H",
    SAVE_CURSOR    => "\x1b[s",
    RESTORE_CURSOR => "\x1b[u",

    # Screen
    CLEAR_SCREEN   => "\x1b[2J",
    CLEAR_LINE     => "\x1b[K",
    RESET_ATTRS    => "\x1b[0m",

    # Mouse modes:
    # ?1000h = basic (press/release only)
    # ?1002h = button-event tracking (reports drag while button pressed)
    # ?1006h = SGR extended mode (larger coordinates, better encoding)
    MOUSE_ENABLE   => "\x1b[?1002h\x1b[?1006h",
    MOUSE_DISABLE  => "\x1b[?1006l\x1b[?1002l",

    # Alternate screen buffer
    ALT_SCREEN_ON  => "\x1b[?1049h",
    ALT_SCREEN_OFF => "\x1b[?1049l",

    # Bracketed paste mode
    PASTE_MODE_ON  => "\x1b[?2004h",
    PASTE_MODE_OFF => "\x1b[?2004l",

    # Cursor shape and color reset
    CURSOR_DEFAULT => "\x1b[0 q",           # Reset cursor shape to default
    CURSOR_COLOR_RESET => "\x1b]112\x1b\\", # OSC 112 - Reset cursor color to default (ST terminator)
};

# Default terminal size and I/O settings
use constant {
    DEFAULT_ROWS    => 24,
    DEFAULT_COLS    => 80,
    READ_BUFFER_SIZE => 1024,
};

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
        in_fh       => $opts{in}  // \*STDIN,
        out_fh      => $opts{out} // \*STDOUT,
        _orig_termios => undef,
        _is_raw     => 0,
        _mouse_on   => 0,
        _alt_screen => 0,
        _rows       => DEFAULT_ROWS,
        _cols       => DEFAULT_COLS,
        _output_buf => '',
    }, $class;

    return $self;
}

# =============================================================================
# Terminal Mode Control
# =============================================================================

# Enter raw mode - disable echo, canonical processing
sub enable_raw_mode {
    my ($self) = @_;
    return if $self->{_is_raw};

    my $in_fh = $self->{in_fh};

    # Save original termios settings
    eval {
        my $termios = POSIX::Termios->new();
        $termios->getattr(fileno($in_fh));
        $self->{_orig_termios} = $termios;

        # Create new termios for raw mode
        my $raw = POSIX::Termios->new();
        $raw->getattr(fileno($in_fh));

        # Get current flags
        my $iflag = $raw->getiflag();
        my $oflag = $raw->getoflag();
        my $cflag = $raw->getcflag();
        my $lflag = $raw->getlflag();

        # Input flags: disable ICRNL (CR->NL), IXON (flow control)
        $iflag &= ~(&POSIX::ICRNL | &POSIX::IXON);
        # Disable BRKINT, INPCK, ISTRIP if available
        $iflag &= ~&POSIX::BRKINT if defined &POSIX::BRKINT;
        $iflag &= ~&POSIX::INPCK if defined &POSIX::INPCK;
        $iflag &= ~&POSIX::ISTRIP if defined &POSIX::ISTRIP;

        # Output flags: disable output processing
        $oflag &= ~&POSIX::OPOST if defined &POSIX::OPOST;

        # Local flags: disable ECHO, ICANON (canonical mode), ISIG (signals)
        # Keep IEXTEN disabled too
        $lflag &= ~(&POSIX::ECHO | &POSIX::ICANON);
        $lflag &= ~&POSIX::ISIG if defined &POSIX::ISIG;
        $lflag &= ~&POSIX::IEXTEN if defined &POSIX::IEXTEN;

        $raw->setiflag($iflag);
        $raw->setoflag($oflag);
        $raw->setcflag($cflag);
        $raw->setlflag($lflag);

        # Set VMIN=1, VTIME=0 for blocking read of at least 1 char
        $raw->setcc(&POSIX::VMIN, 1);
        $raw->setcc(&POSIX::VTIME, 0);

        $raw->setattr(fileno($in_fh), TCSANOW);
    };

    if ($@) {
        warn "Could not enable raw mode: $@";
        return 0;
    }

    $self->{_is_raw} = 1;
    return 1;
}

# Restore original terminal mode
sub disable_raw_mode {
    my ($self) = @_;
    return unless $self->{_is_raw};

    if ($self->{_orig_termios}) {
        eval {
            $self->{_orig_termios}->setattr(fileno($self->{in_fh}), TCSANOW);
        };
    }

    $self->{_is_raw} = 0;
    return 1;
}

sub is_raw { $_[0]->{_is_raw} }

# =============================================================================
# Alternate Screen Buffer
# =============================================================================

sub enter_alt_screen {
    my ($self) = @_;
    return if $self->{_alt_screen};

    $self->write(ALT_SCREEN_ON);
    $self->write(CLEAR_SCREEN);
    $self->write(CURSOR_HOME);
    $self->{_alt_screen} = 1;
    return 1;
}

# Set cursor color using OSC 12
# Color should be in format "#RRGGBB" or a color name
sub set_cursor_color {
    my ($self, $color) = @_;
    return unless $color;
    # OSC 12 ; color ST
    $self->write("\x1b]12;${color}\x1b\\");
    return 1;
}

sub leave_alt_screen {
    my ($self) = @_;
    return unless $self->{_alt_screen};

    $self->write(ALT_SCREEN_OFF);
    $self->{_alt_screen} = 0;
    return 1;
}

# =============================================================================
# Mouse Control
# =============================================================================

sub enable_mouse {
    my ($self) = @_;
    return if $self->{_mouse_on};

    $self->write(MOUSE_ENABLE);
    $self->{_mouse_on} = 1;
    return 1;
}

sub disable_mouse {
    my ($self) = @_;
    return unless $self->{_mouse_on};

    $self->write(MOUSE_DISABLE);
    $self->{_mouse_on} = 0;
    return 1;
}

sub is_mouse_enabled { $_[0]->{_mouse_on} }

# =============================================================================
# Terminal Size
# =============================================================================

# Get terminal size using multiple methods
sub get_size {
    my ($self) = @_;

    my ($rows, $cols);

    # Method 1: ioctl TIOCGWINSZ (may not work on all systems)
    eval {
        local $SIG{__DIE__};  # Don't let outer handlers see this
        require 'sys/ioctl.ph';
        my $winsize = '';
        if (ioctl($self->{out_fh}, &TIOCGWINSZ, $winsize)) {
            ($rows, $cols) = unpack('S!S!', $winsize);
        }
    };

    # Method 2: Environment variables
    if (!$rows || !$cols) {
        $cols = $ENV{COLUMNS} if $ENV{COLUMNS};
        $rows = $ENV{LINES} if $ENV{LINES};
    }

    # Method 3: stty
    if (!$rows || !$cols) {
        my $stty = `stty size 2>/dev/null`;
        if ($stty && $stty =~ /(\d+)\s+(\d+)/) {
            $rows = $1;
            $cols = $2;
        }
    }

    # Method 4: tput
    if (!$rows || !$cols) {
        $cols ||= `tput cols 2>/dev/null`;
        $rows ||= `tput lines 2>/dev/null`;
        chomp($cols) if $cols;
        chomp($rows) if $rows;
    }

    # Fallback defaults
    $rows ||= DEFAULT_ROWS;
    $cols ||= DEFAULT_COLS;

    $self->{_rows} = $rows;
    $self->{_cols} = $cols;

    return ($rows, $cols);
}

sub rows { $_[0]->{_rows} }
sub cols { $_[0]->{_cols} }

# Refresh size (call on SIGWINCH)
sub refresh_size {
    my ($self) = @_;
    return $self->get_size();
}

# =============================================================================
# Input
# =============================================================================

# Read available input (non-blocking)
# Returns bytes read, or empty string if nothing available
sub read_available {
    my ($self, $timeout) = @_;
    $timeout //= 0;

    my $in_fh = $self->{in_fh};
    my $select = IO::Select->new($in_fh);

    my $input = '';

    while ($select->can_read($timeout)) {
        my $buf;
        my $n = sysread($in_fh, $buf, READ_BUFFER_SIZE);
        last unless defined $n && $n > 0;
        $input .= $buf;
        $timeout = 0;  # Don't wait on subsequent reads
    }

    return $input;
}

# Blocking read of at least one byte
sub read_blocking {
    my ($self, $timeout) = @_;
    $timeout //= -1;  # Block forever by default

    my $in_fh = $self->{in_fh};
    my $select = IO::Select->new($in_fh);

    if ($timeout >= 0) {
        return '' unless $select->can_read($timeout);
    }

    my $buf;
    my $n = sysread($in_fh, $buf, READ_BUFFER_SIZE);
    return defined $n ? $buf : '';
}

# Check if input is available
sub has_input {
    my ($self) = @_;
    my $select = IO::Select->new($self->{in_fh});
    return $select->can_read(0) ? 1 : 0;
}

# =============================================================================
# Output
# =============================================================================

# Buffer output (will be flushed together)
sub buffer {
    my ($self, $data) = @_;
    $self->{_output_buf} .= $data if defined $data;
    return length($self->{_output_buf});
}

# Write directly (or from buffer)
sub write {
    my ($self, $data) = @_;

    my $out_fh = $self->{out_fh};
    my $output = ($self->{_output_buf} // '') . ($data // '');
    $self->{_output_buf} = '';

    return unless length $output;

    # Encode UTF-8 for syswrite (which expects bytes, not characters)
    utf8::encode($output) if utf8::is_utf8($output);

    # Use syswrite for unbuffered output
    # Guard against closed filehandle during global destruction
    return 0 unless defined fileno($out_fh);

    my $written = 0;
    while ($written < length($output)) {
        my $n = syswrite($out_fh, $output, length($output) - $written, $written);
        last unless defined $n;
        $written += $n;
    }

    return $written;
}

# Flush output buffer
sub flush {
    my ($self) = @_;
    return $self->write('');
}

# Write with immediate flush
sub print {
    my ($self, $data) = @_;
    return $self->write($data);
}

# =============================================================================
# Cursor Control
# =============================================================================

sub hide_cursor {
    my ($self) = @_;
    $self->write(HIDE_CURSOR);
}

sub show_cursor {
    my ($self) = @_;
    $self->write(SHOW_CURSOR);
}

sub move_cursor {
    my ($self, $row, $col) = @_;
    $self->write("\x1b[${row};${col}H");
}

sub save_cursor {
    my ($self) = @_;
    $self->write(SAVE_CURSOR);
}

sub restore_cursor {
    my ($self) = @_;
    $self->write(RESTORE_CURSOR);
}

# =============================================================================
# Screen Control
# =============================================================================

sub clear_screen {
    my ($self) = @_;
    $self->write(CLEAR_SCREEN);
    $self->write(CURSOR_HOME);
}

sub clear_line {
    my ($self) = @_;
    $self->write(CLEAR_LINE);
}

sub reset_attributes {
    my ($self) = @_;
    $self->write(RESET_ATTRS);
}

# =============================================================================
# Cleanup
# =============================================================================

# Restore terminal to original state
sub cleanup {
    my ($self) = @_;

    # Disable mouse
    $self->disable_mouse() if $self->{_mouse_on};

    # Leave alternate screen
    $self->leave_alt_screen() if $self->{_alt_screen};

    # Reset attributes
    $self->reset_attributes();

    # Reset cursor shape and color to terminal defaults
    $self->write(CURSOR_DEFAULT);
    $self->write(CURSOR_COLOR_RESET);

    # Show cursor
    $self->show_cursor();

    # Flush any pending output
    $self->flush();

    # Restore terminal mode
    $self->disable_raw_mode();
}

# Destructor
sub DESTROY {
    my ($self) = @_;
    $self->cleanup();
}

1;
