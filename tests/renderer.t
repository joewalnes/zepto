#!/usr/bin/env perl
# Tests for Zepto::Renderer
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Zepto::Renderer;
use Zepto::Theme;
use Zepto::Document;
use Zepto::View;
use File::Temp qw(tempfile);

# Helper to create a temp file with content
sub create_temp_file {
    my ($content) = @_;
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh $content;
    close $fh;
    return $filename;
}

# Helper to strip ANSI escape codes for testing
sub strip_escapes {
    my ($str) = @_;
    $str =~ s/\x1b\[[0-9;]*[A-Za-z]//g;
    $str =~ s/\x1b\[\?[0-9]+[hl]//g;
    return $str;
}

# Helper to create document and view for testing
sub create_test_state {
    my ($content) = @_;
    $content //= "Hello World\nLine 2\nLine 3\n";
    my $filename = create_temp_file($content);
    my $doc = Zepto::Document->load($filename);
    my $view = Zepto::View->new(document => $doc);
    return ($doc, $view);
}

# ============================================================================
# Constants
# ============================================================================
subtest 'Constants' => sub {
    is(Zepto::Renderer::ESC, "\x1b", 'ESC constant');
    is(Zepto::Renderer::CSI, "\x1b[", 'CSI constant');
    is(Zepto::Renderer::CURSOR_HOME, "\x1b[H", 'CURSOR_HOME');
    is(Zepto::Renderer::CLEAR_SCREEN, "\x1b[2J", 'CLEAR_SCREEN');
    is(Zepto::Renderer::CLEAR_LINE, "\x1b[K", 'CLEAR_LINE');
    is(Zepto::Renderer::HIDE_CURSOR, "\x1b[?25l", 'HIDE_CURSOR');
    is(Zepto::Renderer::SHOW_CURSOR, "\x1b[?25h", 'SHOW_CURSOR');
    is(Zepto::Renderer::RESET, "\x1b[0m", 'RESET');
};

# ============================================================================
# Basic rendering
# ============================================================================
subtest 'Render returns string' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    ok(defined $output, 'Output is defined');
    ok(length($output) > 0, 'Output has content');
    like($output, qr/\x1b\[/, 'Output contains escape sequences');
};

subtest 'Render structure' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Should start with hide cursor and move to home
    like($output, qr/^\x1b\[\?25l/, 'Starts with hide cursor');
    like($output, qr/\x1b\[H/, 'Contains cursor home');

    # Should end with show cursor (shape set once at editor init, not per render)
    like($output, qr/\x1b\[\?25h$/, 'Ends with show cursor');
};

subtest 'Render without document' => sub {
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => undef,
        view     => undef,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    ok(defined $output, 'Output without doc');
    like($output, qr/No file/, 'Shows no file message');
};

# ============================================================================
# Menu bar
# ============================================================================
subtest 'Menu bar contains menus' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    my $stripped = strip_escapes($output);
    like($stripped, qr/File/, 'Contains File menu');
    like($stripped, qr/Edit/, 'Contains Edit menu');
    like($stripped, qr/Search/, 'Contains Search menu');
    like($stripped, qr/View/, 'Contains View menu');
};

subtest 'Active menu highlighting' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
        ui       => { menu_open => 'f' },
    );

    # Should contain menu active colors (from theme)
    ok(length($output) > 100, 'Has substantial output with menu open');
};

# ============================================================================
# Text area
# ============================================================================
subtest 'Line numbers displayed' => sub {
    my ($doc, $view) = create_test_state("Line 1\nLine 2\nLine 3\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Line numbers should appear
    like($output, qr/1/, 'Contains line 1');
    like($output, qr/2/, 'Contains line 2');
    like($output, qr/3/, 'Contains line 3');
};

subtest 'Content displayed' => sub {
    my ($doc, $view) = create_test_state("Hello World\nFoo Bar\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    like($output, qr/Hello World/, 'Contains first line content');
    like($output, qr/Foo Bar/, 'Contains second line content');
};

subtest 'Empty lines beyond document show tilde' => sub {
    my ($doc, $view) = create_test_state("Short\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Count tildes (should be many for empty lines)
    my $tilde_count = () = $output =~ /~/g;
    ok($tilde_count > 10, 'Has tildes for empty lines');
};

# ============================================================================
# Status bar
# ============================================================================
subtest 'Status bar shows filename' => sub {
    my $content = "Test content\n";
    my $filename = create_temp_file($content);
    my $doc = Zepto::Document->load($filename);
    my $view = Zepto::View->new(document => $doc);
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    like($output, qr/\.txt/, 'Shows filename');
};

subtest 'Status bar shows modified indicator' => sub {
    my ($doc, $view) = create_test_state("Original\n");
    $doc->insert(0, "Modified: ");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    like($output, qr/\*/, 'Shows modified indicator (*)');
};

subtest 'Status bar shows cursor position' => sub {
    my ($doc, $view) = create_test_state("Hello\nWorld\n");
    $view->move_down();
    $view->move_right();
    $view->move_right();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    like($output, qr/Ln\s+2/, 'Shows line number');
    like($output, qr/Col\s+3/, 'Shows column number');
};

subtest 'Menu bar shows Esc and action buttons' => sub {
    my ($doc, $view) = create_test_state("Test\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Menu bar has [Esc] prefix and Save/Quit buttons on right
    like($output, qr/\[Esc\]/, 'Shows [Esc] prefix');
    like($output, qr/Save\s+\^S/, 'Shows Save button');
    like($output, qr/Quit\s+\^Q/, 'Shows Quit button');
};

# ============================================================================
# Dropdown menus
# ============================================================================
subtest 'File menu items' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
        ui       => { menu_open => 'f', menu_selected => 0 },
    );

    like($output, qr/Save/, 'File menu has Save');
    like($output, qr/Quit/, 'File menu has Quit');
    like($output, qr/Ctrl\+S/, 'Shows shortcut');
};

subtest 'Edit menu items' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
        ui       => { menu_open => 'e', menu_selected => 0 },
    );

    like($output, qr/Undo/, 'Edit menu has Undo');
    like($output, qr/Redo/, 'Edit menu has Redo');
    like($output, qr/Cut/, 'Edit menu has Cut');
    like($output, qr/Copy/, 'Edit menu has Copy');
    like($output, qr/Paste/, 'Edit menu has Paste');
};

subtest 'Search menu items' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
        ui       => { menu_open => 's', menu_selected => 0 },
    );

    like($output, qr/Find/, 'Search menu has Find');
    like($output, qr/Replace/, 'Search menu has Replace');
    like($output, qr/Go to Line/, 'Search menu has Go to Line');
};

# ============================================================================
# Dialogs
# ============================================================================
subtest 'Dialog rendering' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
        ui       => {
            dialog => {
                title  => 'Find',
                prompt => 'Search for:',
                value  => 'test',
                cursor => 4,
            },
        },
    );

    like($output, qr/Find/, 'Dialog shows title');
    like($output, qr/Search for/, 'Dialog shows prompt');
    like($output, qr/test/, 'Dialog shows value');
};

subtest 'Dialog box characters' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
        ui       => {
            dialog => {
                title  => 'Test',
                prompt => 'Input:',
                value  => '',
            },
        },
    );

    # Box drawing characters - use constants from Renderer
    my $top_left = Zepto::Renderer::BOX_TOP_LEFT;
    my $top_right = Zepto::Renderer::BOX_TOP_RIGHT;
    my $bottom_left = Zepto::Renderer::BOX_BOTTOM_LEFT;
    my $bottom_right = Zepto::Renderer::BOX_BOTTOM_RIGHT;

    like($output, qr/$top_left/, 'Has top-left corner');
    like($output, qr/$top_right/, 'Has top-right corner');
    like($output, qr/$bottom_left/, 'Has bottom-left corner');
    like($output, qr/$bottom_right/, 'Has bottom-right corner');
};

# ============================================================================
# Selection highlighting
# ============================================================================
subtest 'Selection highlighting' => sub {
    my ($doc, $view) = create_test_state("Hello World\n");
    # Move to 'W'
    $view->move_right() for (1..6);
    # Select "World" by moving with extend_selection=1
    $view->move_right(1) for (1..5);

    ok($view->has_selection(), 'Selection is active');
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    my $stripped = strip_escapes($output);
    # Should contain both text
    like($stripped, qr/Hello/, 'Contains text before selection');
    like($stripped, qr/World/, 'Contains selected text');
    # Should contain selection colors (selection_bg from theme - Tokyo Night blue)
    like($output, qr/\x1b\[48;2;51;70;124m/, 'Contains selection background color');
};

# ============================================================================
# Terminal size handling
# ============================================================================
subtest 'Small terminal' => sub {
    my ($doc, $view) = create_test_state("Short\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 10,
        cols     => 40,
    );

    ok(defined $output, 'Renders on small terminal');
    ok(length($output) > 0, 'Has output');
};

subtest 'Very small terminal' => sub {
    my ($doc, $view) = create_test_state("Test\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 5,
        cols     => 20,
    );

    ok(defined $output, 'Renders on very small terminal');
};

subtest 'Large terminal' => sub {
    my ($doc, $view) = create_test_state("Test\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 100,
        cols     => 200,
    );

    ok(defined $output, 'Renders on large terminal');
    # Should have many tildes for empty lines
    my $tilde_count = () = $output =~ /~/g;
    ok($tilde_count > 50, 'Many tildes on large terminal');
};

# ============================================================================
# Cursor positioning
# ============================================================================
subtest 'Cursor position escape sequence' => sub {
    my ($doc, $view) = create_test_state("Hello\nWorld\n");
    $view->move_down();
    $view->move_right() for (1..3);

    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Cursor is positioned via escape sequence (shape set once at editor init)
    like($output, qr/\x1b\[\d+;\d+H/, 'Contains cursor position escape');
};

# ============================================================================
# Theme integration
# ============================================================================
subtest 'Light theme rendering' => sub {
    my ($doc, $view) = create_test_state("Test\n");
    my $theme = Zepto::Theme->light_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    ok(defined $output, 'Renders with light theme');
    ok(length($output) > 0, 'Has output');
};

subtest 'Both themes produce different output' => sub {
    my ($doc1, $view1) = create_test_state("Test\n");
    my ($doc2, $view2) = create_test_state("Test\n");

    my $dark_output = Zepto::Renderer->render(
        document => $doc1,
        view     => $view1,
        theme    => Zepto::Theme->dark_theme(),
        rows     => 24,
        cols     => 80,
    );

    my $light_output = Zepto::Renderer->render(
        document => $doc2,
        view     => $view2,
        theme    => Zepto::Theme->light_theme(),
        rows     => 24,
        cols     => 80,
    );

    isnt($dark_output, $light_output, 'Different themes produce different output');
};

# ============================================================================
# Default values
# ============================================================================
subtest 'Default terminal size' => sub {
    my ($doc, $view) = create_test_state("Test\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
    );

    ok(defined $output, 'Renders with default size');
};

# ============================================================================
# Structural invariants - catch alignment/positioning bugs
# ============================================================================
subtest 'Menu bar rendered on row 1' => sub {
    my ($doc, $view) = create_test_state("Test\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 10,
        cols     => 80,
    );

    # Menu bar is positioned at row 1, contains File, Edit, etc.
    # Check that output starts with cursor positioning to row 1
    ok($output =~ /\x1b\[1;1H.*?File.*?Edit.*?View/s,
        'Menu bar rendered at row 1 with menu items');
};

subtest 'Text area uses cursor positioning' => sub {
    my ($doc, $view) = create_test_state("Line 1\nLine 2\nLine 3\n");
    my $theme = Zepto::Theme->dark_theme();
    my $rows = 10;
    my $cols = 80;

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => $rows,
        cols     => $cols,
    );

    # Text area rows should use explicit cursor positioning (CSI row;1H)
    # Row 2 is the first text row (after menu bar on row 1)
    my $row2_pos_count = () = $output =~ /\x1b\[2;1H/g;
    my $row3_pos_count = () = $output =~ /\x1b\[3;1H/g;

    ok($row2_pos_count >= 1, "Row 2 cursor positioning present");
    ok($row3_pos_count >= 1, "Row 3 cursor positioning present");
};

subtest 'Text lines have consistent column alignment' => sub {
    my ($doc, $view) = create_test_state("AAA\nBBB\nCCC\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 10,
        cols     => 80,
    );

    # Check that AAA, BBB, CCC all appear in output
    ok($output =~ /AAA/, 'Found AAA in output');
    ok($output =~ /BBB/, 'Found BBB in output');
    ok($output =~ /CCC/, 'Found CCC in output');

    # Check that line numbers 1, 2, 3 appear before content
    # Strip escape codes to check structure
    my $stripped = strip_escapes($output);
    ok($stripped =~ /1\s+AAA/s, 'Line 1 has AAA');
    ok($stripped =~ /2\s+BBB/s, 'Line 2 has BBB');
    ok($stripped =~ /3\s+CCC/s, 'Line 3 has CCC');
};

# =============================================================================
# Menu position calculation
# =============================================================================

subtest 'Dynamic menu positions' => sub {
    my $positions = Zepto::Renderer::get_menu_positions();

    # Verify all menus have positions
    for my $key (qw(f e s v)) {
        ok(exists $positions->{$key}, "Menu '$key' has position");
        ok(exists $positions->{$key}{start}, "Menu '$key' has start");
        ok(exists $positions->{$key}{end}, "Menu '$key' has end");
        ok(exists $positions->{$key}{x}, "Menu '$key' has x");
    }

    # Verify positions are contiguous (no gaps between menus)
    my @keys = qw(f e s v);
    for my $i (1 .. $#keys) {
        my $prev_end = $positions->{$keys[$i-1]}{end};
        my $curr_start = $positions->{$keys[$i]}{start};
        is($curr_start, $prev_end + 1, "Menu '$keys[$i]' starts right after '$keys[$i-1]'");
    }

    # Verify menu widths match expected (name length + 2 for spaces)
    my %expected_widths = (f => 6, e => 6, s => 8, v => 6);  # " File " " Edit " " Search " " View "
    for my $key (keys %expected_widths) {
        my $width = $positions->{$key}{end} - $positions->{$key}{start} + 1;
        is($width, $expected_widths{$key}, "Menu '$key' has correct width");
    }
};

done_testing();
