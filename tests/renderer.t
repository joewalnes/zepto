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
use Zepto::Chars;
use Zepto::Minimap;
use Zepto::Preferences;
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

    # Strip escape sequences - crosshair column highlighting inserts escapes
    # between characters, so we need to strip them to find text content
    my $stripped = strip_escapes($output);
    like($stripped, qr/Hello World/, 'Contains first line content');
    like($stripped, qr/Foo Bar/, 'Contains second line content');
};

subtest 'Empty lines beyond document use distinct background' => sub {
    my ($doc, $view) = create_test_state("Short\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Check for empty_line_bg color (rgb 20,21,30 for dark theme)
    like($output, qr/\x1b\[48;2;20;21;30m/, 'Has empty line background color');
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

    # Modified indicator uses the 'modified' icon from Chars
    my $modified_icon = Zepto::Chars->get('modified');
    like($output, qr/\Q$modified_icon\E/, 'Shows modified indicator icon');
};

subtest 'Ruler bar shows cursor column' => sub {
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

    # Ruler bar shows cursor column badge (1-indexed column number)
    # Cursor is at col 2 (0-indexed), displayed as 3 (1-indexed)
    # The badge appears in the ruler bar (row 3)
    my $stripped = strip_escapes($output);
    like($stripped, qr/ 3/, 'Ruler shows cursor column badge');
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

    # Menu bar has esc prefix (in pill format) and buttons on right
    like($output, qr/esc/, 'Shows esc prefix');
    like($output, qr/\^S/, 'Shows Save shortcut');
    like($output, qr/\^Q/, 'Shows Quit shortcut');
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

    # Box drawing characters - use Chars module (rounded by default with powerline)
    my $top_left = Zepto::Chars->get('box_tl');
    my $top_right = Zepto::Chars->get('box_tr');
    my $bottom_left = Zepto::Chars->get('box_bl');
    my $bottom_right = Zepto::Chars->get('box_br');

    like($output, qr/\Q$top_left\E/, 'Has top-left corner');
    like($output, qr/\Q$top_right\E/, 'Has top-right corner');
    like($output, qr/\Q$bottom_left\E/, 'Has bottom-left corner');
    like($output, qr/\Q$bottom_right\E/, 'Has bottom-right corner');
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
    # Should have empty line background for lines beyond document
    like($output, qr/\x1b\[48;2;20;21;30m/, 'Has empty line background on large terminal');
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
    # Row 2 is the tab bar, Row 3 is the ruler bar
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

    # Strip escape codes to check content
    # Crosshair column highlighting inserts escapes between characters
    my $stripped = strip_escapes($output);

    # Check that AAA, BBB, CCC all appear in stripped output
    ok($stripped =~ /AAA/, 'Found AAA in output');
    ok($stripped =~ /BBB/, 'Found BBB in output');
    ok($stripped =~ /CCC/, 'Found CCC in output');

    # Check that line numbers 1, 2, 3 appear before content
    # Note: cursor line (1) has powerline chars between number and content
    ok($stripped =~ /1.{0,5}AAA/s, 'Line 1 has AAA');
    ok($stripped =~ /2.{0,5}BBB/s, 'Line 2 has BBB');
    ok($stripped =~ /3.{0,5}CCC/s, 'Line 3 has CCC');
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

    # Verify positions have gaps for spaces between pills
    my @keys = qw(f e s v);
    for my $i (1 .. $#keys) {
        my $prev_end = $positions->{$keys[$i-1]}{end};
        my $curr_start = $positions->{$keys[$i]}{start};
        # Now menus have 1 space between them (end + 2 = start)
        is($curr_start, $prev_end + 2, "Menu '$keys[$i]' starts after space from '$keys[$i-1]'");
    }

    # Verify menu widths match expected (name length + 4 for pill + 2 for icon when powerline enabled)
    my %expected_widths = (f => 10, e => 10, s => 12, v => 10);  # pill chars + icon + space + name + space
    for my $key (keys %expected_widths) {
        my $width = $positions->{$key}{end} - $positions->{$key}{start} + 1;
        is($width, $expected_widths{$key}, "Menu '$key' has correct width");
    }
};

# =============================================================================
# Dropdown menu rendering
# =============================================================================
subtest 'Dropdown left border has background color' => sub {
    # This test verifies that the left border of dropdown menus
    # sets BOTH background and foreground colors, not just foreground.
    # Without the background color, the left edge shows terminal default
    # (black) which appears as an inverted bar in light themes.

    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->get_theme('light');

    my $ui = {
        menu_open => 'f',      # File menu open
        menu_selected => 0,
    };

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
        ui       => $ui,
    );

    # Get the box_v character and theme colors
    my $box_v = Zepto::Chars->get('box_v');
    my $dropdown_bg = $theme->color('dropdown_bg');
    my $dropdown_border = $theme->color('dropdown_border');

    # Find all instances of box_v (vertical borders) in output
    # Each left border should be preceded by both bg and fg colors
    # Pattern: bg_color + border_color + box_v
    my $expected_prefix = quotemeta($dropdown_bg) . quotemeta($dropdown_border) . quotemeta($box_v);

    # Count how many times the left border appears with correct colors
    my $correct_borders = () = $output =~ /$expected_prefix/g;

    # We expect at least several (one per menu item row)
    # File menu has ~7 items, so at least 7 left borders
    cmp_ok($correct_borders, '>=', 5, 'Left borders have both bg and fg colors set');

    # Also verify we don't have borders with ONLY foreground (the bug)
    # Pattern: move_to + border_color (without bg) + box_v
    # This would be: \x1b[row;colH + border_color + box_v (no bg between position and border)
    my $move_pattern = qr/\x1b\[\d+;\d+H/;
    my $bad_pattern = qr/$move_pattern\Q$dropdown_border\E\Q$box_v\E/;

    my $bad_borders = () = $output =~ /$bad_pattern/g;
    is($bad_borders, 0, 'No left borders missing background color');
};

# ============================================================================
# Gutter width calculation
# ============================================================================
subtest 'Gutter width accommodates cursor line badge' => sub {
    # The cursor line has a badge: round_left + line_number + space + arrow_right
    # Badge width = 1 + digits + 1 + 1 = digits + 3
    # Gutter must be wide enough for this

    # Test with various line counts
    my @test_cases = (
        { lines => 99,    max_digits => 2, expected_min => 5 },  # "99" + 3 = 5
        { lines => 100,   max_digits => 3, expected_min => 6 },  # "100" + 3 = 6
        { lines => 320,   max_digits => 3, expected_min => 6 },  # "320" + 3 = 6
        { lines => 999,   max_digits => 3, expected_min => 6 },  # "999" + 3 = 6
        { lines => 1000,  max_digits => 4, expected_min => 7 },  # "1000" + 3 = 7
        { lines => 10000, max_digits => 5, expected_min => 8 },  # "10000" + 3 = 8
    );

    for my $tc (@test_cases) {
        my $gutter = Zepto::Renderer->get_gutter_width($tc->{lines});
        my $badge_width = $tc->{max_digits} + 3;  # round_left + digits + space + arrow_right

        cmp_ok($gutter, '>=', $badge_width,
            "Gutter ($gutter) fits badge ($badge_width) for $tc->{lines} lines");
    }
};

subtest 'Gutter width is stable across document' => sub {
    # Verify gutter width doesn't change as we scroll through document
    # This would cause text to shift left/right
    my $content = join("\n", map { "Line $_" } (1..320));
    my ($doc, $view) = create_test_state($content);

    my $gutter_at_start = Zepto::Renderer->get_gutter_width($doc->line_count());

    # Scroll to various positions - gutter should always be the same
    for my $scroll_to (0, 50, 99, 150, 200, 300) {
        $view->set_cursor($scroll_to, 0);
        my $gutter = Zepto::Renderer->get_gutter_width($doc->line_count());
        is($gutter, $gutter_at_start,
            "Gutter width stable when viewing line $scroll_to");
    }
};

# =============================================================================
# Inline diff expansion rendering
# =============================================================================

use Zepto::LineMap;

subtest 'Expanded modified hunk renders old and new lines' => sub {
    my ($doc, $view) = create_test_state("Line A\nLine B\nLine C\nLine D\nLine E\n");
    my $theme = Zepto::Theme->dark_theme();

    # Create a modified hunk: base lines [0,1] replaced current lines [1,2]
    my @hunks = ({
        type           => 'modified',
        base_lines     => [0, 1],
        current_lines  => [1, 2],
        prev_curr_line => 0,
        next_curr_line => 3,
    });

    my $lm = Zepto::LineMap->new(
        doc_line_count => $doc->line_count(),
        hunks          => \@hunks,
    );
    $lm->toggle_hunk(0);
    $view->set_line_map($lm);

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 15,
        cols     => 80,
    );

    ok(defined $output, 'Output produced with expanded hunk');
    ok(length($output) > 0, 'Output has content');

    # The output should contain the diff_old_bg color (rgb 60,30,30 for dark theme)
    my $old_bg = "\x1b[48;2;60;30;30m";
    like($output, qr/\Q$old_bg\E/, 'Output contains diff_old_bg color for old lines');

    # Should also contain diff_new_bg color (rgb 30,55,30)
    my $new_bg = "\x1b[48;2;30;55;30m";
    like($output, qr/\Q$new_bg\E/, 'Output contains diff_new_bg color for new lines');

    # Expanded hunk lines should have full block char in gutter (█ = \x{2588})
    my $stripped = strip_escapes($output);
    like($stripped, qr/\x{2588}/, 'Expanded lines display full block in gutter');
};

subtest 'Expanded deleted hunk shows only old lines' => sub {
    my ($doc, $view) = create_test_state("Line A\nLine B\nLine C\n");
    my $theme = Zepto::Theme->dark_theme();

    my @hunks = ({
        type           => 'deleted',
        base_lines     => [0, 1],
        current_lines  => [],
        prev_curr_line => 0,
        next_curr_line => 1,
    });

    my $lm = Zepto::LineMap->new(
        doc_line_count => $doc->line_count(),
        hunks          => \@hunks,
    );
    $lm->toggle_hunk(0);
    $view->set_line_map($lm);

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 12,
        cols     => 80,
    );

    # Should have old-line bg but no new-line bg (no current_lines in hunk)
    my $old_bg = "\x1b[48;2;60;30;30m";
    like($output, qr/\Q$old_bg\E/, 'Deleted hunk shows old lines with red bg');

    # Total display rows = 3 doc + 2 old = 5
    is($lm->total_display_rows(), 5, 'LineMap shows 5 display rows');
};

subtest 'Expanded added hunk shows green bg, no old lines' => sub {
    my ($doc, $view) = create_test_state("Line A\nLine B\nLine C\nLine D\n");
    my $theme = Zepto::Theme->dark_theme();

    my @hunks = ({
        type           => 'added',
        base_lines     => [],
        current_lines  => [1, 2],
        prev_curr_line => 0,
        next_curr_line => 3,
    });

    my $lm = Zepto::LineMap->new(
        doc_line_count => $doc->line_count(),
        hunks          => \@hunks,
    );
    $lm->toggle_hunk(0);
    $view->set_line_map($lm);

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 12,
        cols     => 80,
    );

    # Should have green bg for added lines
    my $new_bg = "\x1b[48;2;30;55;30m";
    like($output, qr/\Q$new_bg\E/, 'Added hunk shows green bg');

    # No red bg (no old lines)
    my $old_bg = "\x1b[48;2;60;30;30m";
    unlike($output, qr/\Q$old_bg\E/, 'No red bg for added-only hunk');

    # Total display rows unchanged (no old lines to insert)
    is($lm->total_display_rows(), 4, 'LineMap shows 4 display rows (no old lines)');
};

subtest 'Collapse hunk restores normal rendering' => sub {
    my ($doc, $view) = create_test_state("Line A\nLine B\nLine C\n");
    my $theme = Zepto::Theme->dark_theme();

    my @hunks = ({
        type           => 'modified',
        base_lines     => [0],
        current_lines  => [0],
        prev_curr_line => -1,
        next_curr_line => 1,
    });

    my $lm = Zepto::LineMap->new(
        doc_line_count => $doc->line_count(),
        hunks          => \@hunks,
    );
    $view->set_line_map($lm);

    # Render without expansion — no diff colors
    my $output_normal = Zepto::Renderer->render(
        document => $doc, view => $view, theme => $theme, rows => 10, cols => 80,
    );

    # Expand, then collapse
    $lm->toggle_hunk(0);
    $lm->toggle_hunk(0);

    my $output_collapsed = Zepto::Renderer->render(
        document => $doc, view => $view, theme => $theme, rows => 10, cols => 80,
    );

    my $old_bg = "\x1b[48;2;60;30;30m";
    unlike($output_collapsed, qr/\Q$old_bg\E/, 'No red bg after collapse');

    is($lm->total_display_rows(), 3, 'Display rows back to normal after collapse');
};

subtest 'screen_to_doc returns undef for old-line rows' => sub {
    my ($doc, $view) = create_test_state("Line A\nLine B\nLine C\nLine D\nLine E\n");

    my @hunks = ({
        type           => 'modified',
        base_lines     => [0, 1],
        current_lines  => [1, 2],
        prev_curr_line => 0,
        next_curr_line => 3,
    });

    my $lm = Zepto::LineMap->new(
        doc_line_count => $doc->line_count(),
        hunks          => \@hunks,
    );
    $lm->toggle_hunk(0);
    $view->set_line_map($lm);
    $view->set_viewport_size(10, 60);

    # Display: row 0=doc0, row 1=old0, row 2=old1, row 3=doc1(green), row 4=doc2(green), row 5=doc3, row 6=doc4

    # Row 0 -> doc line 0
    my ($line0, $col0) = $view->screen_to_doc(0, 0);
    is($line0, 0, 'Screen row 0 maps to doc line 0');

    # Row 1 -> old line (should return undef)
    my ($line1, $col1) = $view->screen_to_doc(1, 0);
    is($line1, undef, 'Screen row 1 (old line) returns undef');

    # Row 2 -> old line (should return undef)
    my ($line2, $col2) = $view->screen_to_doc(2, 0);
    is($line2, undef, 'Screen row 2 (old line) returns undef');

    # Row 3 -> doc line 1
    my ($line3, $col3) = $view->screen_to_doc(3, 0);
    is($line3, 1, 'Screen row 3 maps to doc line 1');

    # Row 5 -> doc line 3
    my ($line5, $col5) = $view->screen_to_doc(5, 0);
    is($line5, 3, 'Screen row 5 maps to doc line 3');
};

subtest 'doc_to_screen accounts for expanded hunks' => sub {
    my ($doc, $view) = create_test_state("A\nB\nC\nD\nE\n");

    my @hunks = ({
        type           => 'modified',
        base_lines     => [0, 1],
        current_lines  => [1, 2],
        prev_curr_line => 0,
        next_curr_line => 3,
    });

    my $lm = Zepto::LineMap->new(
        doc_line_count => $doc->line_count(),
        hunks          => \@hunks,
    );
    $lm->toggle_hunk(0);
    $view->set_line_map($lm);
    $view->set_viewport_size(10, 60);

    # Doc line 0 at display row 0 -> screen row 0
    my ($row0, $col0) = $view->doc_to_screen(0, 0);
    is($row0, 0, 'Doc line 0 at screen row 0');

    # Doc line 1 at display row 3 (after 2 old lines) -> screen row 3
    my ($row1, $col1) = $view->doc_to_screen(1, 0);
    is($row1, 3, 'Doc line 1 at screen row 3 (after 2 old lines)');

    # Doc line 4 at display row 6
    my ($row4, $col4) = $view->doc_to_screen(4, 0);
    is($row4, 6, 'Doc line 4 at screen row 6');
};

subtest 'Light theme diff colors in expanded hunk' => sub {
    my ($doc, $view) = create_test_state("Line A\nLine B\nLine C\n");
    my $theme = Zepto::Theme->light_theme();

    my @hunks = ({
        type           => 'modified',
        base_lines     => [0],
        current_lines  => [0],
        prev_curr_line => -1,
        next_curr_line => 1,
    });

    my $lm = Zepto::LineMap->new(
        doc_line_count => $doc->line_count(),
        hunks          => \@hunks,
    );
    $lm->toggle_hunk(0);
    $view->set_line_map($lm);

    my $output = Zepto::Renderer->render(
        document => $doc, view => $view, theme => $theme, rows => 10, cols => 80,
    );

    # Light theme uses different RGB values
    my $old_bg_light = "\x1b[48;2;255;220;220m";
    # Cursor is on line 0 (the hunk line), so it gets diff_new_cursor_bg
    my $new_cursor_bg_light = "\x1b[48;2;200;245;200m";

    like($output, qr/\Q$old_bg_light\E/, 'Light theme has pink bg for old lines');
    like($output, qr/\Q$new_cursor_bg_light\E/, 'Light theme has green cursor bg for hunk line');
};

# ============================================================================
# Minimap
# ============================================================================

subtest 'Minimap not shown when disabled' => sub {
    # Create a long document (longer than viewport)
    my $content = join('', map { "Line $_\n" } (1..50));
    my ($doc, $view) = create_test_state($content);
    my $theme = Zepto::Theme->dark_theme();
    my $prefs = Zepto::Preferences->new(show_minimap => 0);

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        prefs    => $prefs,
        rows     => 24,
        cols     => 80,
    );

    # Braille chars (U+2800-U+28FF) should NOT appear
    unlike($output, qr/[\x{2800}-\x{28FF}]/, 'No braille chars when minimap disabled');
};

subtest 'Minimap not shown for short documents' => sub {
    my ($doc, $view) = create_test_state("Line 1\nLine 2\nLine 3\n");
    my $theme = Zepto::Theme->dark_theme();
    my $prefs = Zepto::Preferences->new(show_minimap => 1);

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        prefs    => $prefs,
        rows     => 24,
        cols     => 80,
    );

    # 3 lines < 20 text rows, so minimap should auto-hide
    unlike($output, qr/[\x{2800}-\x{28FF}]/, 'No braille chars for short document');
};

subtest 'Minimap shown for long documents' => sub {
    my $content = join('', map { "Line number $_ with some content here\n" } (1..50));
    my ($doc, $view) = create_test_state($content);
    my $theme = Zepto::Theme->dark_theme();
    my $prefs = Zepto::Preferences->new(show_minimap => 1);

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        prefs    => $prefs,
        rows     => 24,
        cols     => 80,
    );

    # Braille chars should appear for text density
    like($output, qr/[\x{2800}-\x{28FF}]/, 'Braille chars present for long document');

    # Minimap separator (│) should appear
    my $sep = Zepto::Chars->get('minimap_sep');
    like($output, qr/\Q$sep\E/, 'Minimap separator present');

    # Minimap background color should appear
    like($output, qr/\x1b\[48;2;22;23;34m/, 'Minimap bg color present');
};

subtest 'Minimap viewport highlight' => sub {
    my $content = join('', map { "Line number $_ with some content here\n" } (1..100));
    my ($doc, $view) = create_test_state($content);
    $view->{viewport_rows} = 20;
    my $theme = Zepto::Theme->dark_theme();
    my $prefs = Zepto::Preferences->new(show_minimap => 1);

    my $output = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        prefs    => $prefs,
        rows     => 24,
        cols     => 80,
    );

    # Viewport highlight bg should appear
    like($output, qr/\x1b\[48;2;45;50;72m/, 'Minimap viewport highlight bg present');
};

subtest 'Minimap width constant matches module' => sub {
    is(Zepto::Renderer::MINIMAP_WIDTH, Zepto::Minimap::MINIMAP_TOTAL_WIDTH,
       'Renderer MINIMAP_WIDTH matches Minimap module');
};

subtest 'get_minimap_width returns 0 when disabled' => sub {
    my $prefs = Zepto::Preferences->new(show_minimap => 0);
    my $width = Zepto::Renderer->get_minimap_width(100, 20, 80, 5, $prefs);
    is($width, 0, 'Minimap width is 0 when disabled');
};

subtest 'get_minimap_width returns 0 for short documents' => sub {
    my $prefs = Zepto::Preferences->new(show_minimap => 1);
    my $width = Zepto::Renderer->get_minimap_width(10, 20, 80, 5, $prefs);
    is($width, 0, 'Minimap width is 0 when doc shorter than viewport');
};

subtest 'get_minimap_width returns MINIMAP_WIDTH for long documents' => sub {
    my $prefs = Zepto::Preferences->new(show_minimap => 1);
    my $width = Zepto::Renderer->get_minimap_width(100, 20, 80, 5, $prefs);
    is($width, Zepto::Renderer::MINIMAP_WIDTH, 'Minimap width is MINIMAP_WIDTH for long doc');
};

subtest 'get_minimap_width returns 0 for narrow terminal' => sub {
    my $prefs = Zepto::Preferences->new(show_minimap => 1);
    # cols=20, gutter=5, minimap=8 => text=7 < MIN_TEXT_WIDTH=10
    my $width = Zepto::Renderer->get_minimap_width(100, 20, 20, 5, $prefs);
    is($width, 0, 'Minimap hidden for narrow terminal');
};

done_testing();
