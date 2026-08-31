#!/usr/bin/env perl
# Tests for Zepto::Terminal
# Note: Some functionality requires actual terminal, so we test what we can
use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::Terminal;
use Zepto::ImageConverter;
use File::Temp qw(tempfile);

# ============================================================================
# Constants
# ============================================================================
subtest 'Constants' => sub {
    is(Zepto::Terminal::ESC, "\x1b", 'ESC constant');
    is(Zepto::Terminal::HIDE_CURSOR, "\x1b[?25l", 'HIDE_CURSOR');
    is(Zepto::Terminal::SHOW_CURSOR, "\x1b[?25h", 'SHOW_CURSOR');
    is(Zepto::Terminal::CURSOR_HOME, "\x1b[H", 'CURSOR_HOME');
    is(Zepto::Terminal::CLEAR_SCREEN, "\x1b[2J", 'CLEAR_SCREEN');
    is(Zepto::Terminal::CLEAR_LINE, "\x1b[K", 'CLEAR_LINE');
    is(Zepto::Terminal::RESET_ATTRS, "\x1b[0m", 'RESET_ATTRS');
    like(Zepto::Terminal::MOUSE_ENABLE, qr/\x1b\[\?1003h/, 'MOUSE_ENABLE (any-event tracking)');
    like(Zepto::Terminal::MOUSE_DISABLE, qr/\x1b\[\?1003l/, 'MOUSE_DISABLE');
    like(Zepto::Terminal::ALT_SCREEN_ON, qr/\x1b\[\?1049h/, 'ALT_SCREEN_ON');
    like(Zepto::Terminal::ALT_SCREEN_OFF, qr/\x1b\[\?1049l/, 'ALT_SCREEN_OFF');
};

# ============================================================================
# Construction
# ============================================================================
subtest 'Construction' => sub {
    my $term = Zepto::Terminal->new();
    ok($term, 'Terminal created');
    ok(!$term->is_raw(), 'Not in raw mode initially');
    ok(!$term->is_mouse_enabled(), 'Mouse not enabled initially');
};

subtest 'Construction with custom handles' => sub {
    my ($in_fh, $in_name) = tempfile(UNLINK => 1);
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);

    my $term = Zepto::Terminal->new(in => $in_fh, out => $out_fh);
    ok($term, 'Terminal with custom handles');
};

# ============================================================================
# Output buffering
# ============================================================================
subtest 'Output buffering' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    # Buffer some output
    $term->buffer("Hello");
    $term->buffer(" World");

    # Verify buffer length
    my $len = $term->buffer("");
    is($len, 11, 'Buffer has 11 chars');

    # Flush and verify
    $term->flush();

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };
    is($output, "Hello World", 'Buffered output written');
};

subtest 'Direct write' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->write("Direct output");

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };
    is($output, "Direct output", 'Direct write works');
};

subtest 'Print method' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->print("Print output");

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };
    is($output, "Print output", 'Print works');
};

# ============================================================================
# Cursor control output
# ============================================================================
subtest 'Cursor control' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->hide_cursor();
    $term->move_cursor(10, 20);
    $term->show_cursor();

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };

    like($output, qr/\x1b\[\?25l/, 'Hide cursor sequence');
    like($output, qr/\x1b\[10;20H/, 'Move cursor sequence');
    like($output, qr/\x1b\[\?25h/, 'Show cursor sequence');
};

subtest 'Save/restore cursor' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->save_cursor();
    $term->restore_cursor();

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };

    like($output, qr/\x1b\[s/, 'Save cursor');
    like($output, qr/\x1b\[u/, 'Restore cursor');
};

# ============================================================================
# Screen control output
# ============================================================================
subtest 'Screen control' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->clear_screen();
    $term->clear_line();
    $term->reset_attributes();

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };

    like($output, qr/\x1b\[2J/, 'Clear screen');
    like($output, qr/\x1b\[K/, 'Clear line');
    like($output, qr/\x1b\[0m/, 'Reset attributes');
};

# ============================================================================
# Size methods (with defaults)
# ============================================================================
subtest 'Size defaults' => sub {
    my $term = Zepto::Terminal->new();

    # Initial values before any size detection
    is($term->rows(), 24, 'Default rows');
    is($term->cols(), 80, 'Default cols');
};

subtest 'Get size returns values' => sub {
    my $term = Zepto::Terminal->new();
    my ($rows, $cols) = $term->get_size();

    ok(defined $rows, 'Rows returned');
    ok(defined $cols, 'Cols returned');
    ok($rows > 0, 'Rows positive');
    ok($cols > 0, 'Cols positive');
};

subtest 'Pixel dimension defaults and accessors' => sub {
    my $term = Zepto::Terminal->new();

    # Before get_size, pixel dimensions default to 0
    is($term->xpixel(), 0, 'Default xpixel is 0');
    is($term->ypixel(), 0, 'Default ypixel is 0');
    is($term->cell_width_px(), 0, 'cell_width_px returns 0 when no pixel info');
    is($term->cell_height_px(), 0, 'cell_height_px returns 0 when no pixel info');

    # Fallback aspect ratio should be 2.0 when pixel info unavailable
    is($term->cell_aspect_ratio(), 2.0, 'cell_aspect_ratio fallback is 2.0');

    # After get_size, pixel values may or may not be populated depending on
    # terminal, but accessors should return defined values
    $term->get_size();
    ok(defined $term->xpixel(), 'xpixel defined after get_size');
    ok(defined $term->ypixel(), 'ypixel defined after get_size');
    ok(defined $term->cell_width_px(), 'cell_width_px defined after get_size');
    ok(defined $term->cell_height_px(), 'cell_height_px defined after get_size');
    ok($term->cell_aspect_ratio() > 0, 'cell_aspect_ratio is positive');
};

subtest 'cell_aspect_ratio computes from pixel dimensions' => sub {
    my $term = Zepto::Terminal->new();
    # Simulate a terminal reporting 1600x800 pixels for 80x24
    $term->{_xpixel} = 1600;
    $term->{_ypixel} = 800;
    $term->{_cols} = 80;
    $term->{_rows} = 40;

    # cell_width = 1600/80 = 20, cell_height = 800/40 = 20
    # aspect = 20/20 = 1.0
    is($term->cell_width_px(), 20, 'cell_width_px = 1600/80 = 20');
    is($term->cell_height_px(), 20, 'cell_height_px = 800/40 = 20');
    is($term->cell_aspect_ratio(), 1.0, 'cell_aspect_ratio = 20/20 = 1.0');
};

# ============================================================================
# Mouse state
# ============================================================================
subtest 'Mouse state tracking' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    ok(!$term->is_mouse_enabled(), 'Mouse initially off');

    $term->enable_mouse();
    ok($term->is_mouse_enabled(), 'Mouse now on');

    $term->disable_mouse();
    ok(!$term->is_mouse_enabled(), 'Mouse now off');
};

subtest 'Mouse enable idempotent' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->enable_mouse();
    $term->enable_mouse();  # Second call should be no-op

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };

    # Count enable sequences - should only be one
    my $count = () = $output =~ /\x1b\[\?1003h/g;
    is($count, 1, 'Mouse enabled only once');
};

# ============================================================================
# Alt screen state
# ============================================================================
subtest 'Alt screen state tracking' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->enter_alt_screen();

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };
    like($output, qr/\x1b\[\?1049h/, 'Alt screen enter');
};

subtest 'Alt screen idempotent' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->enter_alt_screen();
    $term->enter_alt_screen();  # Should be no-op

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };

    my $count = () = $output =~ /\x1b\[\?1049h/g;
    is($count, 1, 'Alt screen entered only once');
};

# ============================================================================
# Input (basic checks without real terminal)
# ============================================================================
subtest 'Has input with no data' => sub {
    my ($in_fh, $in_name) = tempfile(UNLINK => 1);
    # File is empty, so no input available

    my $term = Zepto::Terminal->new(in => $in_fh);
    # With a file, select() behavior varies - just check it doesn't crash
    ok(defined $term->has_input(), 'has_input returns defined value');
};

# ============================================================================
# System Clipboard
# ============================================================================
subtest 'Clipboard command detection' => sub {
    my $term = Zepto::Terminal->new();

    # On macOS, should detect pbcopy/pbpaste
    # On other systems, may or may not have clipboard support
    # Just verify the detection runs without error
    ok(defined $term->has_system_clipboard(), 'has_system_clipboard returns defined value');

    if ($^O eq 'darwin') {
        ok($term->has_system_clipboard(), 'macOS should have pbcopy');
        is_deeply($term->{_clipboard_copy_cmd}, ['pbcopy'], 'Copy command is pbcopy');
        is_deeply($term->{_clipboard_paste_cmd}, ['pbpaste'], 'Paste command is pbpaste');
    }
};

subtest 'copy_to_clipboard generates OSC 52' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->copy_to_clipboard("hello");

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };

    # Should contain OSC 52 sequence with base64 encoded "hello"
    # "hello" in base64 is "aGVsbG8="
    like($output, qr/\x1b\]52;c;aGVsbG8=\x1b\\/, 'OSC 52 sequence generated');
};

subtest 'copy_to_clipboard handles empty/undef' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    $term->copy_to_clipboard('');
    $term->copy_to_clipboard(undef);

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };

    # Should not output anything for empty/undef
    unlike($output, qr/\x1b\]52/, 'No OSC 52 for empty input');
};

subtest 'copy_to_clipboard handles wide characters' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    # Copy text with double-width CJK characters — should not crash
    my $wide_text = "\x{4e16}\x{754c}";  # 世界 (CJK characters)
    eval { $term->copy_to_clipboard($wide_text) };
    is($@, '', 'No crash copying wide characters');

    seek($out_fh, 0, 0);
    my $output = do { local $/; <$out_fh> };

    # Should contain OSC 52 with base64-encoded UTF-8 bytes
    # "世界" in UTF-8 is \xe4\xb8\x96\xe7\x95\x8c, base64 is "5LiW55WM"
    like($output, qr/\x1b\]52;c;5LiW55WM\x1b\\/, 'OSC 52 correct for wide chars');

    # Also test emoji (multi-byte + wide display)
    my ($out_fh2, $out_name2) = tempfile(UNLINK => 1);
    my $term2 = Zepto::Terminal->new(out => $out_fh2);
    eval { $term2->copy_to_clipboard("\x{1f600}") };  # 😀
    is($@, '', 'No crash copying emoji');
};

subtest 'paste_from_clipboard returns string' => sub {
    my $term = Zepto::Terminal->new();

    # Should return a string (possibly empty if no clipboard support)
    my $result = $term->paste_from_clipboard();
    ok(defined $result, 'paste_from_clipboard returns defined value');
    ok(!ref($result), 'paste_from_clipboard returns scalar');
};

subtest 'paste_from_clipboard decodes UTF-8' => sub {
    plan skip_all => 'Requires macOS pbcopy/pbpaste' unless $^O eq 'darwin';

    my $term = Zepto::Terminal->new();

    # Copy a unicode string via pbcopy, then paste it back
    my $test_str = "box ─ drawing \x{2500} emoji \x{1f600}";
    my $bytes = $test_str;
    utf8::encode($bytes);
    my $pid = open(my $pipe, '|-', 'pbcopy');
    if ($pid) {
        binmode($pipe, ':raw');
        print $pipe $bytes;
        close $pipe;
    }

    my $result = $term->paste_from_clipboard();
    ok(utf8::is_utf8($result), 'Pasted text has UTF-8 flag set');
    is($result, $test_str, 'UTF-8 round-trip through clipboard preserves characters');
};

# Regression test for bugs.md P1 "Clipboard paste has no timeout -- a
# hung paste command freezes the UI indefinitely" / QA-REG-188. Before
# the fix, paste_from_clipboard() did a bare blocking `<$fh>` slurp with
# no alarm() guard (unlike FindEngine.pm's MATCH_ALARM_SECS pattern), so
# a wedged clipboard command (e.g. wl-paste with no reachable Wayland
# compositor, or a hung powershell.exe under WSL) would freeze the whole
# editor forever with no recovery path.
subtest 'paste_from_clipboard times out on a hung clipboard command' => sub {
    my $term = Zepto::Terminal->new();

    # Simulate a wedged platform clipboard command: 'sleep' comfortably
    # outlives CLIPBOARD_PASTE_ALARM_SECS (3s) but is portable (POSIX
    # standard, no macOS/Linux-specific flags) and self-terminates so the
    # test process doesn't leak a runaway child if something goes wrong.
    $term->{_clipboard_paste_cmd} = ['sleep', '30'];

    my $start = time();
    my $result = $term->paste_from_clipboard();
    my $elapsed = time() - $start;

    ok(!defined $result,
        'Returns undef on timeout -- distinct from "" (empty clipboard), so callers can tell the difference');
    ok($elapsed < Zepto::Terminal::CLIPBOARD_PASTE_ALARM_SECS + 3,
        "Returns promptly after the alarm fires (${elapsed}s), not after the full 30s hang")
        or diag('paste_from_clipboard is blocking past its alarm -- the timeout guard has regressed');
};

# ============================================================================
# Cleanup
# ============================================================================
subtest 'Cleanup resets state' => sub {
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    my $term = Zepto::Terminal->new(out => $out_fh);

    # Enable some things
    $term->enable_mouse();

    # Cleanup should disable them
    $term->cleanup();

    ok(!$term->is_mouse_enabled(), 'Mouse disabled after cleanup');
};

# ============================================================================
# Kitty Graphics Protocol
# ============================================================================
subtest 'Kitty graphics support detection' => sub {
    # Result is memoized, so we can only verify it returns a defined boolean
    my $result = Zepto::Terminal->supports_kitty_graphics();
    ok(defined $result, 'supports_kitty_graphics returns defined value');
    ok($result == 0 || $result == 1, 'supports_kitty_graphics returns 0 or 1');
};

subtest 'Kitty graphics image display sequence' => sub {
    my $dir = File::Temp::tempdir(CLEANUP => 1);
    my $img_path = "$dir/test.png";

    # Create a minimal valid PNG (1x1 red pixel)
    # PNG signature + IHDR + IDAT + IEND
    my $png = pack('H*',
        '89504e470d0a1a0a' .  # PNG signature
        '0000000d49484452' .  # IHDR chunk length + type
        '00000001' .          # width: 1
        '00000001' .          # height: 1
        '0802000000' .        # 8-bit RGB
        '907753de' .          # IHDR CRC
        '0000000c4944415478' .  # IDAT
        '9c6260f80f000001' .
        '01006718d33e' .
        '0000000049454e44ae426082'  # IEND
    );
    open my $fh, '>:raw', $img_path or die;
    print $fh $png;
    close $fh;

    my $seq = Zepto::Terminal->kitty_display_image(
        path   => $img_path,
        row    => 3,
        col    => 5,
        width  => 40,
        height => 20,
        id     => 42,
    );

    # Should start with cursor positioning
    like($seq, qr/\x1b\[3;5H/, 'Image sequence starts with cursor positioning');

    # Should contain Kitty graphics APC
    like($seq, qr/\x1b_G/, 'Contains Kitty graphics APC start');

    # Should have correct parameters
    like($seq, qr/a=T/, 'Action is transmit+display');
    like($seq, qr/f=100/, 'Format is PNG/image');
    like($seq, qr/i=42/, 'Image ID is set');
    like($seq, qr/c=40/, 'Width in cells');
    like($seq, qr/r=20/, 'Height in cells');
    like($seq, qr/C=1/, 'Cursor movement suppressed');

    # Should end with ST
    like($seq, qr/\x1b\\/, 'Ends with String Terminator');
};

subtest 'Kitty graphics clear sequence' => sub {
    my $clear_all = Zepto::Terminal->kitty_clear_image();
    like($clear_all, qr/\x1b_Ga=d,d=A\x1b\\/, 'Clear all images');

    my $clear_one = Zepto::Terminal->kitty_clear_image(42);
    like($clear_one, qr/\x1b_Ga=d,d=I,i=42\x1b\\/, 'Clear specific image');
};

subtest 'Image converter detection' => sub {
    my $converter = Zepto::ImageConverter->detect_converter();
    ok(defined $converter, 'detect_converter returns defined value');
    if ($converter) {
        like($converter, qr/sips|convert/, 'Detected sips or convert');
        ok(-x $converter, 'Converter is executable');
    }
};

subtest 'ensure_png passes through PNG files' => sub {
    my $dir = File::Temp::tempdir(CLEANUP => 1);
    my $png_path = "$dir/test.png";

    # Write minimal PNG
    open my $fh, '>:raw', $png_path;
    print $fh pack('H*', '89504e470d0a1a0a0000000d494844520000000100000001' .
        '0100000000376ef9240000000a49444154789c626001000000050001e98aab' .
        '6c0000000049454e44ae426082');
    close $fh;

    my $result = Zepto::ImageConverter->ensure_png($png_path);
    is($result, $png_path, 'PNG file returned as-is');
};

subtest 'ensure_png converts JPEG to PNG' => sub {
    my $converter = Zepto::ImageConverter->detect_converter();
    plan skip_all => 'No image converter available' unless $converter;

    my $dir = File::Temp::tempdir(CLEANUP => 1);
    my $jpg_path = "$dir/test.jpg";

    # Create a real JPEG from an 8-bit RGB PNG source (JPEG needs >=8-bit)
    my $src_png = "$dir/src.png";
    open my $pfh, '>:raw', $src_png;
    print $pfh pack('H*',
        '89504e470d0a1a0a0000000d4948445200000002000000020802000000' .
        'fdd49a730000001449444154789c63f8cfc0c000c20cffffff67000' .
        '01eef04fca3c8b4f70000000049454e44ae426082');
    close $pfh;

    # Suppress converter output (sips prints paths to stdout)
    open my $old_out, '>&', \*STDOUT;
    open my $old_err, '>&', \*STDERR;
    open STDOUT, '>', '/dev/null';
    open STDERR, '>', '/dev/null';
    my $created;
    if ($converter =~ /sips$/) {
        $created = system($converter, '-s', 'format', 'jpeg', $src_png,
               '--out', $jpg_path) == 0;
    } else {
        $created = system($converter, $src_png, $jpg_path) == 0;
    }
    open STDOUT, '>&', $old_out;
    open STDERR, '>&', $old_err;
    plan skip_all => 'Could not create test JPEG' unless $created;
    plan skip_all => 'JPEG test file not created' unless -f $jpg_path;

    my $result = Zepto::ImageConverter->ensure_png($jpg_path);
    ok($result, 'ensure_png returned a path for JPEG');
    if ($result) {
        isnt($result, $jpg_path, 'Converted path differs from original');
        ok(-f $result, 'Converted PNG file exists');
        # Verify it's actually a PNG
        open my $rfh, '<:raw', $result;
        read($rfh, my $magic, 4);
        close $rfh;
        is($magic, "\x89PNG", 'Converted file has PNG magic bytes');
    }

    Zepto::ImageConverter::cleanup();
};

subtest 'ensure_png returns empty for non-image without converter' => sub {
    my $dir = File::Temp::tempdir(CLEANUP => 1);
    my $txt_path = "$dir/test.txt";
    open my $fh, '>', $txt_path;
    print $fh "not an image";
    close $fh;

    my $result = Zepto::ImageConverter->ensure_png($txt_path);
    # Either converted (unlikely for .txt) or empty — either is acceptable
    ok(defined $result, 'ensure_png returns defined value for non-image');
};

done_testing();
