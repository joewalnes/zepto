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
use Zepto::ImageConverter;

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

    # Terminal title (OSC 0 sets both icon and window title)
    TITLE_SET      => "\x1b]0;",            # OSC 0 - Set title (needs ST terminator)
    TITLE_END      => "\x07",               # BEL terminator for title
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
        _xpixel     => 0,
        _ypixel     => 0,
        _output_buf => '',
        _clipboard_copy_cmd  => undef,
        _clipboard_paste_cmd => undef,
    }, $class;

    # Ensure output handle is in raw/bytes mode — Terminal encodes
    # UTF-8 manually before syswrite, so :utf8 layers must be removed
    binmode($self->{out_fh}, ':raw');

    # Detect platform clipboard commands
    $self->_detect_clipboard_commands();

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

    # Clear the alternate screen before leaving — some terminals don't
    # fully restore the main screen buffer, leaving alt screen content
    # visible above the cursor position.
    $self->write(CLEAR_SCREEN);
    $self->write(CURSOR_HOME);
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

# Bracketed paste mode — lets us detect terminal-level paste (Cmd+V)
sub enable_bracketed_paste {
    my ($self) = @_;
    $self->write(PASTE_MODE_ON);
    $self->{_bracketed_paste} = 1;
}

sub disable_bracketed_paste {
    my ($self) = @_;
    return unless $self->{_bracketed_paste};
    $self->write(PASTE_MODE_OFF);
    $self->{_bracketed_paste} = 0;
}

# =============================================================================
# Terminal Size
# =============================================================================

# Get terminal size using multiple methods
sub get_size {
    my ($self) = @_;

    my ($rows, $cols);

    # Method 1: ioctl TIOCGWINSZ (may not work on all systems)
    my $got_ioctl;
    eval {
        local $SIG{__DIE__};  # Don't let outer handlers see this
        require 'sys/ioctl.ph';
        my $winsize = '';
        if (ioctl($self->{out_fh}, &TIOCGWINSZ, $winsize)) {
            ($rows, $cols, my $xpx, my $ypx) = unpack('S!S!S!S!', $winsize);
            $self->{_xpixel} = $xpx || 0;
            $self->{_ypixel} = $ypx || 0;
            $got_ioctl = 1;
        }
    };

    # If rows/cols need a fallback source, pixel values from ioctl would be
    # inconsistent — reset them to avoid stale cell-size calculations
    if (!$rows || !$cols) {
        $self->{_xpixel} = 0;
        $self->{_ypixel} = 0;
    }

    # Method 2: Environment variables
    if (!$rows || !$cols) {
        $cols = $ENV{COLUMNS} if $ENV{COLUMNS} && $ENV{COLUMNS} =~ /^\d+$/;
        $rows = $ENV{LINES} if $ENV{LINES} && $ENV{LINES} =~ /^\d+$/;
    }

    # Method 3: stty
    if (!$rows || !$cols) {
        my $stty = _safe_backtick('stty', 'size');
        if ($stty && $stty =~ /(\d+)\s+(\d+)/) {
            $rows = $1;
            $cols = $2;
        }
    }

    # Method 4: tput
    if (!$rows || !$cols) {
        $cols ||= _safe_backtick('tput', 'cols');
        $rows ||= _safe_backtick('tput', 'lines');
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
sub xpixel { $_[0]->{_xpixel} }
sub ypixel { $_[0]->{_ypixel} }

sub cell_width_px {
    my ($self) = @_;
    return 0 unless $self->{_xpixel} && $self->{_cols};
    return $self->{_xpixel} / $self->{_cols};
}

sub cell_height_px {
    my ($self) = @_;
    return 0 unless $self->{_ypixel} && $self->{_rows};
    return $self->{_ypixel} / $self->{_rows};
}

sub cell_aspect_ratio {
    my ($self) = @_;
    my $cw = $self->cell_width_px();
    my $ch = $self->cell_height_px();
    return 2.0 unless $cw > 0 && $ch > 0;
    return $ch / $cw;
}

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
# System Clipboard
# =============================================================================

# Detect available clipboard commands for the current platform
sub _detect_clipboard_commands {
    my ($self) = @_;

    # macOS
    if ($^O eq 'darwin') {
        if (_command_exists('pbcopy')) {
            $self->{_clipboard_copy_cmd} = ['pbcopy'];
            $self->{_clipboard_paste_cmd} = ['pbpaste'];
            return;
        }
    }
    # Linux/BSD with X11
    elsif (_command_exists('xclip')) {
        $self->{_clipboard_copy_cmd} = ['xclip', '-selection', 'clipboard'];
        $self->{_clipboard_paste_cmd} = ['xclip', '-selection', 'clipboard', '-o'];
        return;
    }
    elsif (_command_exists('xsel')) {
        $self->{_clipboard_copy_cmd} = ['xsel', '--clipboard', '--input'];
        $self->{_clipboard_paste_cmd} = ['xsel', '--clipboard', '--output'];
        return;
    }
    # Wayland
    elsif (_command_exists('wl-copy')) {
        $self->{_clipboard_copy_cmd} = ['wl-copy'];
        $self->{_clipboard_paste_cmd} = ['wl-paste'];
        return;
    }
    # WSL
    elsif (_command_exists('clip.exe')) {
        $self->{_clipboard_copy_cmd} = ['clip.exe'];
        # paste on WSL requires PowerShell
        $self->{_clipboard_paste_cmd} = ['powershell.exe', '-command', 'Get-Clipboard'];
        return;
    }

    # No clipboard command found - OSC 52 will still work for copy
}

sub _command_exists {
    my ($cmd) = @_;
    my $check = _safe_backtick('which', $cmd);
    return defined $check && $check ne '' && $? == 0;
}

# Run a command with list-form exec (no shell interpretation), suppressing stderr.
# Returns the command's stdout output.
sub _safe_backtick {
    my (@cmd) = @_;
    my $pid = open(my $fh, '-|');
    return '' unless defined $pid;
    if ($pid == 0) {
        open(STDERR, '>', '/dev/null');
        exec(@cmd) or exit(127);
    }
    my $output = do { local $/; <$fh> };
    close($fh);
    return defined $output ? $output : '';
}

# Copy text to system clipboard
# Uses both OSC 52 (for terminal support) and platform command (as fallback)
sub copy_to_clipboard {
    my ($self, $text) = @_;
    return unless defined $text && length $text;

    # Encode to UTF-8 bytes — encode_base64 and pipe write expect bytes,
    # not Perl's internal wide character strings
    my $bytes = $text;
    utf8::encode($bytes) if utf8::is_utf8($bytes);

    # Method 1: OSC 52 escape sequence
    # Works in modern terminals, through tmux (with set-clipboard on), over SSH
    require MIME::Base64;
    my $encoded = MIME::Base64::encode_base64($bytes, '');
    # OSC 52 ; c ; base64-data ST (ST = \x1b\\)
    $self->write("\x1b]52;c;${encoded}\x1b\\");

    # Method 2: Platform clipboard command (list-form exec, no shell)
    if ($self->{_clipboard_copy_cmd}) {
        my $pid = open(my $pipe, '|-', @{$self->{_clipboard_copy_cmd}});
        if ($pid) {
            binmode($pipe, ':raw');
            print $pipe $bytes;
            close $pipe;
        }
    }

    return 1;
}

# Read text from system clipboard
# Returns clipboard contents or empty string if unavailable
sub paste_from_clipboard {
    my ($self) = @_;

    return '' unless $self->{_clipboard_paste_cmd};

    my @cmd = @{$self->{_clipboard_paste_cmd}};
    my $pid = open(my $fh, '-|');
    return '' unless defined $pid;
    if ($pid == 0) {
        open(STDERR, '>', '/dev/null');
        exec(@cmd) or exit(127);
    }
    binmode($fh, ':raw');
    my $text = do { local $/; <$fh> };
    close($fh);
    return '' unless defined $text;
    utf8::decode($text);
    return $text;
}

# Check if system clipboard is available
sub has_system_clipboard {
    my ($self) = @_;
    return defined $self->{_clipboard_copy_cmd};
}

# =============================================================================
# Terminal Title
# =============================================================================

sub set_title {
    my ($self, $title) = @_;
    # Strip C0 control chars (0x00-0x1F), DEL (0x7F), and C1 control chars (0x80-0x9F)
    # to prevent OSC sequence injection via file names
    $title =~ s/[\x00-\x1f\x7f\x80-\x9f]//g;
    $self->write(TITLE_SET . $title . TITLE_END);
    $self->flush();
}

sub restore_title {
    my ($self) = @_;
    # Reset title by setting empty title (most terminals restore default)
    $self->write(TITLE_SET . TITLE_END);
    $self->flush();
}

# =============================================================================
# Cleanup
# =============================================================================

sub cleanup {
    my ($self) = @_;

    # Disable mouse
    $self->disable_mouse() if $self->{_mouse_on};

    # Disable bracketed paste
    $self->disable_bracketed_paste();

    # Leave alternate screen
    $self->leave_alt_screen() if $self->{_alt_screen};

    # Reset attributes
    $self->reset_attributes();

    # Reset cursor shape and color to terminal defaults
    $self->write(CURSOR_DEFAULT);
    $self->write(CURSOR_COLOR_RESET);

    # Restore terminal title
    $self->restore_title();

    # Show cursor
    $self->show_cursor();

    # Clean up converted image temp files
    Zepto::ImageConverter::cleanup();

    # Flush any pending output
    $self->flush();

    # Restore terminal mode
    $self->disable_raw_mode();
}

# =============================================================================
# Kitty Graphics Protocol
# =============================================================================

{
    my $_kitty_graphics_supported;

    sub supports_kitty_graphics {
        return $_kitty_graphics_supported if defined $_kitty_graphics_supported;
        my $term_program = $ENV{TERM_PROGRAM} // '';
        my $term = $ENV{TERM} // '';
        $_kitty_graphics_supported = (
            $term_program eq 'ghostty'
            || $term_program eq 'kitty'
            || $term =~ /kitty/i
            || defined $ENV{KITTY_WINDOW_ID}
        ) ? 1 : 0;
        return $_kitty_graphics_supported;
    }

    # Reset cache (for testing with different TERM_PROGRAM values)
    sub _reset_kitty_cache {
        $_kitty_graphics_supported = undef;
    }
}

# Display an image at a specific position using Kitty graphics protocol.
# Sends image data inline as base64-encoded PNG.
# Non-PNG images are converted via sips (macOS) or convert (ImageMagick).
# Returns empty string if image cannot be rendered.
sub kitty_display_image {
    my ($class, %args) = @_;
    my $path   = $args{path};
    my $row    = $args{row};     # 1-based terminal row
    my $col    = $args{col};     # 1-based terminal column
    my $width  = $args{width};   # display width in cells
    my $height = $args{height};  # display height in cells
    my $id     = $args{id} // 1; # image ID for later reference

    require MIME::Base64;

    # Ensure we have a PNG (convert if necessary)
    $path = Zepto::ImageConverter->ensure_png($path);
    return '' unless $path;

    # Read image data
    open my $fh, '<:raw', $path or return '';
    my $data = do { local $/; <$fh> };
    close $fh;
    return '' unless defined $data && length($data) > 0;

    my $b64 = MIME::Base64::encode_base64($data, '');
    my $chunk_size = 4096;

    # Position cursor
    my $output = "\x1b[${row};${col}H";

    if (length($b64) <= $chunk_size) {
        # Single chunk
        $output .= sprintf("\x1b_Ga=T,f=100,i=%d,c=%d,r=%d,C=1,q=2;%s\x1b\\",
            $id, $width, $height, $b64);
    } else {
        # Chunked transmission
        my $first = substr($b64, 0, $chunk_size, '');
        $output .= sprintf("\x1b_Ga=T,f=100,i=%d,c=%d,r=%d,C=1,q=2,m=1;%s\x1b\\",
            $id, $width, $height, $first);

        while (length($b64) > $chunk_size) {
            my $chunk = substr($b64, 0, $chunk_size, '');
            $output .= sprintf("\x1b_Gm=1;%s\x1b\\", $chunk);
        }

        # Final chunk
        $output .= sprintf("\x1b_Gm=0;%s\x1b\\", $b64);
    }

    return $output;
}

# Clear a specific image or all images
sub kitty_clear_image {
    my ($class, $id) = @_;
    if ($id) {
        return sprintf("\x1b_Ga=d,d=I,i=%d\x1b\\", $id);
    }
    return "\x1b_Ga=d,d=A\x1b\\";  # clear all
}

# Destructor
sub DESTROY {
    my ($self) = @_;
    $self->cleanup();
}

1;
