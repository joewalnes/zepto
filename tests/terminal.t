#!/usr/bin/env perl
# Tests for Zepto::Terminal
# Note: Some functionality requires actual terminal, so we test what we can
use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::Terminal;
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
    like(Zepto::Terminal::MOUSE_ENABLE, qr/\x1b\[\?1002h/, 'MOUSE_ENABLE (button-event tracking)');
    like(Zepto::Terminal::MOUSE_DISABLE, qr/\x1b\[\?1002l/, 'MOUSE_DISABLE');
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
    my $count = () = $output =~ /\x1b\[\?1002h/g;
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
        is($term->{_clipboard_copy_cmd}, 'pbcopy', 'Copy command is pbcopy');
        is($term->{_clipboard_paste_cmd}, 'pbpaste', 'Paste command is pbpaste');
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

subtest 'paste_from_clipboard returns string' => sub {
    my $term = Zepto::Terminal->new();

    # Should return a string (possibly empty if no clipboard support)
    my $result = $term->paste_from_clipboard();
    ok(defined $result, 'paste_from_clipboard returns defined value');
    ok(!ref($result), 'paste_from_clipboard returns scalar');
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

done_testing();
