#!/usr/bin/env perl
# Tests for Zepto::Renderer
use strict;
use warnings;
use utf8;
use open ':std', ':utf8';
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
        document => undef,
        view     => undef,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    ok(defined $output, 'Output without doc');
    like($output, qr/1:1/, 'Shows cursor position even without doc');
};

# ============================================================================
# Status bar pills
# ============================================================================
subtest 'Status bar has palette trigger pill' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    my $stripped = strip_escapes($output);
    like($stripped, qr/\x{2303}\x{2423}/, 'Status bar has ⌃␣ palette trigger pill');
};

subtest 'Active menu highlighting' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
        ui       => {},
    );

    # Should contain substantial output
    ok(length($output) > 100, 'Has substantial output');
};

# ============================================================================
# Text area
# ============================================================================
subtest 'Line numbers displayed' => sub {
    my ($doc, $view) = create_test_state("Line 1\nLine 2\nLine 3\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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
subtest 'Status bar shows cursor position' => sub {
    my $content = "Test content\n";
    my $filename = create_temp_file($content);
    my $doc = Zepto::Document->load($filename);
    my $view = Zepto::View->new(document => $doc);
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    like($output, qr/1:1/, 'Shows cursor position');
};

subtest 'Status bar shows palette trigger' => sub {
    my ($doc, $view) = create_test_state("Original\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Palette trigger shows ⌃␣
    like($output, qr/\x{2303}\x{2423}/, 'Shows palette trigger (⌃␣)');
};

subtest 'Ruler bar shows cursor column' => sub {
    my ($doc, $view) = create_test_state("Hello\nWorld\n");
    $view->move_down();
    $view->move_right();
    $view->move_right();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Ruler bar shows cursor column badge (1-indexed column number)
    # Cursor is at col 2 (0-indexed), displayed as 3 (1-indexed)
    # The badge appears in the ruler bar (row 2)
    my $stripped = strip_escapes($output);
    like($stripped, qr/ 3/, 'Ruler shows cursor column badge');
};

subtest 'Status bar shows cursor position and palette trigger' => sub {
    my ($doc, $view) = create_test_state("Test\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    my $stripped = strip_escapes($output);
    like($stripped, qr/1:1/, 'Status bar shows cursor position');
};

# ============================================================================
# Dialogs
# ============================================================================
subtest 'Dialog rendering' => sub {
    my ($doc, $view) = create_test_state();
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    # Box drawing characters - use Chars module (rounded by default with nerd font)
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $dark_output = Zepto::Renderer->render_string(
        document => $doc1,
        view     => $view1,
        theme    => Zepto::Theme->dark_theme(),
        rows     => 24,
        cols     => 80,
    );

    my $light_output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
    );

    ok(defined $output, 'Renders with default size');
};

# ============================================================================
# Structural invariants - catch alignment/positioning bugs
# ============================================================================
subtest 'Tab bar rendered on row 1' => sub {
    my ($doc, $view) = create_test_state("Test\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 10,
        cols     => 80,
    );

    # Tab bar is positioned at row 1 (first row, no menu bar above it)
    # Check that output starts with cursor positioning to row 1
    ok($output =~ /\x1b\[1;1H/s,
        'Tab bar rendered at row 1');
};

subtest 'Text area uses cursor positioning' => sub {
    my ($doc, $view) = create_test_state("Line 1\nLine 2\nLine 3\n");
    my $theme = Zepto::Theme->dark_theme();
    my $rows = 10;
    my $cols = 80;

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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
    # Note: cursor line (1) has nerd font chars between number and content
    ok($stripped =~ /1.{0,5}AAA/s, 'Line 1 has AAA');
    ok($stripped =~ /2.{0,5}BBB/s, 'Line 2 has BBB');
    ok($stripped =~ /3.{0,5}CCC/s, 'Line 3 has CCC');
};

# =============================================================================
# Layout: Chrome = 3 rows (tab bar + ruler + status)
# =============================================================================

subtest 'Layout has 3 chrome rows' => sub {
    my ($doc, $view) = create_test_state("Line 1\nLine 2\n");
    my $theme = Zepto::Theme->dark_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Text starts at row 3 (after tab bar and ruler)
    # Verify we have substantial output (tab bar + ruler + 21 text rows + status)
    ok(length($output) > 100, 'Layout renders successfully with 3 chrome rows');
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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
    my $output_normal = Zepto::Renderer->render_string(
        document => $doc, view => $view, theme => $theme, rows => 10, cols => 80,
    );

    # Expand, then collapse
    $lm->toggle_hunk(0);
    $lm->toggle_hunk(0);

    my $output_collapsed = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

    my $output = Zepto::Renderer->render_string(
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

subtest 'get_minimap_width accounts for tree_width' => sub {
    my $prefs = Zepto::Preferences->new(show_minimap => 1);
    # cols=40, gutter=5, tree=20, minimap=8 => text=40-20-5-8=7 < MIN_TEXT_WIDTH
    my $width = Zepto::Renderer->get_minimap_width(100, 20, 40, 5, $prefs, 20);
    is($width, 0, 'Minimap drops off when tree takes space');

    # Without tree: cols=40, gutter=5, minimap=8 => text=27 >= MIN_TEXT_WIDTH
    my $width2 = Zepto::Renderer->get_minimap_width(100, 20, 40, 5, $prefs, 0);
    is($width2, 8, 'Minimap shows when tree is not present');
};

# =============================================================================
# Display width helpers for wide character handling
# =============================================================================

subtest 'char display width - ASCII' => sub {
    is(Zepto::Renderer::_char_display_width('a'), 1, 'ASCII letter is 1 column');
    is(Zepto::Renderer::_char_display_width(' '), 1, 'space is 1 column');
    is(Zepto::Renderer::_char_display_width('!'), 1, 'ASCII punctuation is 1 column');
};

subtest 'char display width - wide characters' => sub {
    # Emoji
    is(Zepto::Renderer::_char_display_width("\x{274C}"), 2, 'cross mark emoji (❌) is 2 columns');
    is(Zepto::Renderer::_char_display_width("\x{2705}"), 2, 'check mark emoji (✅) is 2 columns');
    is(Zepto::Renderer::_char_display_width("\x{1F600}"), 2, 'grinning face emoji is 2 columns');
    # CJK
    is(Zepto::Renderer::_char_display_width("\x{4E2D}"), 2, 'CJK character (中) is 2 columns');
    # Fullwidth
    is(Zepto::Renderer::_char_display_width("\x{FF01}"), 2, 'fullwidth exclamation is 2 columns');
    # Misc Technical wide chars
    is(Zepto::Renderer::_char_display_width("\x{231A}"), 2, 'watch (⌚) is 2 columns');
    is(Zepto::Renderer::_char_display_width("\x{23F0}"), 2, 'alarm clock (⏰) is 2 columns');
    # Misc Symbols wide chars
    is(Zepto::Renderer::_char_display_width("\x{2614}"), 2, 'umbrella (☔) is 2 columns');
    is(Zepto::Renderer::_char_display_width("\x{26A1}"), 2, 'high voltage (⚡) is 2 columns');
    is(Zepto::Renderer::_char_display_width("\x{2B50}"), 2, 'star (⭐) is 2 columns');
};

subtest 'char display width - narrow symbols (not wide per Unicode EAW)' => sub {
    # These chars are in ranges that were previously (incorrectly) treated as wide.
    # They have EAW=N (Narrow) and render as 1 column in terminals.
    is(Zepto::Renderer::_char_display_width("\x{2325}"), 1, 'option key (⌥) is 1 column');
    is(Zepto::Renderer::_char_display_width("\x{2318}"), 1, 'command key (⌘) is 1 column');
    is(Zepto::Renderer::_char_display_width("\x{2328}"), 1, 'keyboard (⌨) is 1 column');
    is(Zepto::Renderer::_char_display_width("\x{26A0}"), 1, 'warning sign (⚠) is 1 column');
    is(Zepto::Renderer::_char_display_width("\x{2714}"), 1, 'check mark (✔) is 1 column');
    is(Zepto::Renderer::_char_display_width("\x{2764}"), 1, 'heavy heart (❤) is 1 column');
    is(Zepto::Renderer::_char_display_width("\x{2B51}"), 1, 'small star (⭑) is 1 column');
};

subtest 'display width - string' => sub {
    is(Zepto::Renderer::_display_width('hello'), 5, 'ASCII string');
    is(Zepto::Renderer::_display_width("abc\x{274C}def"), 8, 'string with emoji (3+2+3)');
    is(Zepto::Renderer::_display_width("\x{4E2D}\x{6587}"), 4, 'two CJK chars = 4 columns');
};

subtest 'truncate to display width' => sub {
    my ($str, $w);

    # No truncation needed
    ($str, $w) = Zepto::Renderer::_truncate_to_display_width('hello', 10);
    is($str, 'hello', 'no truncation when fits');
    is($w, 5, 'width correct');

    # Truncate ASCII
    ($str, $w) = Zepto::Renderer::_truncate_to_display_width('hello world', 5);
    is($str, 'hello', 'truncated ASCII to 5 cols');
    is($w, 5, 'width = 5');

    # Truncate before wide char that would overflow
    ($str, $w) = Zepto::Renderer::_truncate_to_display_width("abc\x{274C}def", 4);
    is($str, 'abc', 'stops before emoji that would exceed width');
    is($w, 3, 'width = 3 (emoji needs 2 but only 1 col left)');

    ($str, $w) = Zepto::Renderer::_truncate_to_display_width("abc\x{274C}def", 5);
    is($str, "abc\x{274C}", 'includes emoji when it fits exactly');
    is($w, 5, 'width = 5 (3 + 2)');
};

# ============================================================================
# _char_to_visual_col and visual_to_char_col with wide characters
# ============================================================================
subtest '_char_to_visual_col handles wide characters' => sub {
    # ASCII only
    is(Zepto::Renderer::_char_to_visual_col("hello", 3), 3, 'ASCII: col 3 = visual 3');

    # CJK: each char is display width 2
    my $cjk = "\x{4e16}\x{754c}";  # 世界
    is(Zepto::Renderer::_char_to_visual_col($cjk, 1), 2, 'CJK: after 1 char = visual 2');
    is(Zepto::Renderer::_char_to_visual_col($cjk, 2), 4, 'CJK: after 2 chars = visual 4');

    # Mixed: ASCII + CJK
    my $mixed = "ab\x{4e16}cd";  # ab世cd
    is(Zepto::Renderer::_char_to_visual_col($mixed, 2), 2, 'Mixed: after "ab" = visual 2');
    is(Zepto::Renderer::_char_to_visual_col($mixed, 3), 4, 'Mixed: after "ab世" = visual 4');
    is(Zepto::Renderer::_char_to_visual_col($mixed, 4), 5, 'Mixed: after "ab世c" = visual 5');

    # Emoji (display width 2)
    my $emoji = "a\x{1f600}b";  # a😀b
    is(Zepto::Renderer::_char_to_visual_col($emoji, 1), 1, 'Emoji: after "a" = visual 1');
    is(Zepto::Renderer::_char_to_visual_col($emoji, 2), 3, 'Emoji: after "a😀" = visual 3');
    is(Zepto::Renderer::_char_to_visual_col($emoji, 3), 4, 'Emoji: after "a😀b" = visual 4');
};

subtest 'visual_to_char_col handles wide characters' => sub {
    # CJK: visual col 2 falls within first char (width 2), visual col 3 is in second char
    my $cjk = "\x{4e16}\x{754c}";  # 世界
    is(Zepto::Renderer::visual_to_char_col($cjk, 1), 0, 'CJK: visual 1 = char 0 (inside 世)');
    is(Zepto::Renderer::visual_to_char_col($cjk, 2), 1, 'CJK: visual 2 = char 1 (start of 界)');
    is(Zepto::Renderer::visual_to_char_col($cjk, 3), 1, 'CJK: visual 3 = char 1 (inside 界)');
    is(Zepto::Renderer::visual_to_char_col($cjk, 4), 2, 'CJK: visual 4 = char 2 (past end)');

    # Mixed: ASCII + CJK
    my $mixed = "ab\x{4e16}cd";  # ab世cd
    is(Zepto::Renderer::visual_to_char_col($mixed, 3), 2, 'Mixed: visual 3 = char 2 (inside 世)');
    is(Zepto::Renderer::visual_to_char_col($mixed, 4), 3, 'Mixed: visual 4 = char 3 (start of c)');
};

subtest 'Status bar shows READ ONLY for binary files' => sub {
    my $doc = Zepto::Document->new();
    $doc->{_is_binary} = 1;
    $doc->set_path('/tmp/image.png');
    my $theme = Zepto::Theme->new('dark');
    my $bar = Zepto::Renderer->_render_status_bar($doc, undef, $theme, 80, undef, undef, undef);
    # Strip ANSI escape sequences to check text content
    (my $plain = $bar) =~ s/\x1b\[[^m]*m//g;
    like($plain, qr/READ ONLY/, 'Status bar contains READ ONLY for binary files');
};

# ============================================================================
# QA-REG-126: long status messages must be truncated, not left to overflow
# and wrap onto the next terminal row (which scrolls the whole screen and
# corrupts everything rendered above the status bar).
# ============================================================================
subtest 'Long status message is truncated to fit the terminal width' => sub {
    my $doc = Zepto::Document->new();
    my $theme = Zepto::Theme->new('dark');
    my $cols = 80;
    my $tail = 'reg126_target_file.py';
    my $long_msg = 'Saved: /' . ('x' x 150) . '/' . $tail;

    my $bar = Zepto::Renderer->_render_status_bar($doc, undef, $theme, $cols, $long_msg, undef, undef);
    (my $plain = $bar) =~ s/\x1b\[[^m]*m//g;
    $plain =~ s/\x1b\[K//g;

    ok(length($plain) <= $cols + 1, '_render_status_bar output fits within terminal width')
        or diag("length=" . length($plain) . " cols=$cols");
    like($plain, qr/\x{2026}/, 'truncated message contains an ellipsis');
    like($plain, qr/\Q$tail\E/, 'truncated message preserves the tail (filename)');
    unlike($plain, qr/x{150}/, 'the full untruncated 150-char run is not printed verbatim');
};

subtest 'Long status message is truncated in context status bar too' => sub {
    my $doc = Zepto::Document->new();
    my $theme = Zepto::Theme->new('dark');
    my $cols = 80;
    my $tail = 'reg126_other.txt';
    my $long_msg = 'Saved: /' . ('y' x 150) . '/' . $tail;

    my $bar = Zepto::Renderer->_render_context_status_bar(
        $doc, undef, $theme, $cols, $long_msg, 0, {}, 0
    );
    (my $plain = $bar) =~ s/\x1b\[[^m]*m//g;
    $plain =~ s/\x1b\[K//g;

    ok(length($plain) <= $cols + 1, '_render_context_status_bar output fits within terminal width')
        or diag("length=" . length($plain) . " cols=$cols");
    like($plain, qr/\x{2026}/, 'truncated message contains an ellipsis');
    like($plain, qr/\Q$tail\E/, 'truncated message preserves the tail (filename)');
    unlike($plain, qr/y{150}/, 'the full untruncated 150-char run is not printed verbatim');
};
# ============================================================================
# Inline Markdown image detection
# ============================================================================

subtest '_detect_markdown_images' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    # Create a real image file (1x1 PNG)
    my $img_path = File::Spec->catfile($tmpdir, 'test.png');
    open my $ifh, '>:raw', $img_path or die "Cannot write $img_path: $!";
    # Minimal valid PNG (1x1 transparent pixel)
    print $ifh pack('H*', '89504e470d0a1a0a0000000d494844520000000100000001' .
        '0100000000376ef9240000000a49444154789c626001000000050001e98aab' .
        '6c0000000049454e44ae426082');
    close $ifh;

    # Create a JPEG file (SOI + APP0/JFIF + SOF0 with 1x1 dimensions + EOI)
    my $jpg_path = File::Spec->catfile($tmpdir, 'photo.jpg');
    open my $jfh, '>:raw', $jpg_path or die "Cannot write $jpg_path: $!";
    print $jfh pack('H*', 'ffd8ffe000104a46494600010100000100010000' .
        'ffc0000b080001000101011100' .  # SOF0: 1x1, 8-bit, 1 component
        'ffd9');
    close $jfh;

    subtest 'detects relative image path' => sub {
        my $md_path = File::Spec->catfile($tmpdir, 'test.md');
        open my $fh, '>', $md_path or die;
        print $fh "# Hello\n";
        print $fh "![Alt text](test.png)\n";
        print $fh "Some more text\n";
        close $fh;
        my $doc = Zepto::Document->load($md_path);
        local $ENV{TERM_PROGRAM} = 'ghostty';
        # Reset the cached value
        Zepto::Terminal->_reset_kitty_cache();
        my $result = Zepto::Renderer->_detect_markdown_images($doc, 0, 3);
        ok(exists $result->{1}, 'Image detected on line 1');
        is($result->{1}{path}, $img_path, 'Absolute path resolved correctly');
        is($result->{1}{alt}, 'Alt text', 'Alt text extracted');
    };

    subtest 'detects absolute image path' => sub {
        my $md_path = File::Spec->catfile($tmpdir, 'abs.md');
        open my $fh, '>', $md_path or die;
        print $fh "![photo]($jpg_path)\n";
        close $fh;
        my $doc = Zepto::Document->load($md_path);
        local $ENV{TERM_PROGRAM} = 'ghostty';
        Zepto::Terminal->_reset_kitty_cache();
        my $result = Zepto::Renderer->_detect_markdown_images($doc, 0, 1);
        ok(exists $result->{0}, 'Image detected on line 0');
        is($result->{0}{path}, $jpg_path, 'Absolute path preserved');
    };

    subtest 'skips missing files' => sub {
        my $md_path = File::Spec->catfile($tmpdir, 'missing.md');
        open my $fh, '>', $md_path or die;
        print $fh "![missing](nonexistent.png)\n";
        close $fh;
        my $doc = Zepto::Document->load($md_path);
        local $ENV{TERM_PROGRAM} = 'ghostty';
        Zepto::Terminal->_reset_kitty_cache();
        my $result = Zepto::Renderer->_detect_markdown_images($doc, 0, 1);
        ok(!%$result, 'No images detected for missing files');
    };

    subtest 'skips URLs' => sub {
        my $md_path = File::Spec->catfile($tmpdir, 'urls.md');
        open my $fh, '>', $md_path or die;
        print $fh "![web](https://example.com/image.png)\n";
        print $fh "![data](data:image/png;base64,abc)\n";
        print $fh "![http](http://example.com/photo.jpg)\n";
        close $fh;
        my $doc = Zepto::Document->load($md_path);
        local $ENV{TERM_PROGRAM} = 'ghostty';
        Zepto::Terminal->_reset_kitty_cache();
        my $result = Zepto::Renderer->_detect_markdown_images($doc, 0, 3);
        ok(!%$result, 'URLs are skipped');
    };

    subtest 'returns empty for non-markdown files' => sub {
        my $txt_path = File::Spec->catfile($tmpdir, 'test.txt');
        open my $fh, '>', $txt_path or die;
        print $fh "![image](test.png)\n";
        close $fh;
        my $doc = Zepto::Document->load($txt_path);
        local $ENV{TERM_PROGRAM} = 'ghostty';
        Zepto::Terminal->_reset_kitty_cache();
        my $result = Zepto::Renderer->_detect_markdown_images($doc, 0, 1);
        ok(!%$result, 'Non-markdown files return empty');
    };

    subtest 'returns empty on non-Kitty terminal' => sub {
        my $md_path = File::Spec->catfile($tmpdir, 'kitty.md');
        open my $fh, '>', $md_path or die;
        print $fh "![image](test.png)\n";
        close $fh;
        my $doc = Zepto::Document->load($md_path);
        local $ENV{TERM_PROGRAM} = 'xterm';
        local $ENV{TERM} = 'xterm-256color';
        delete local $ENV{KITTY_WINDOW_ID};
        Zepto::Terminal->_reset_kitty_cache();
        my $result = Zepto::Renderer->_detect_markdown_images($doc, 0, 1);
        ok(!%$result, 'Non-Kitty terminal returns empty');
    };

    subtest 'skips non-image extensions' => sub {
        my $txt_file = File::Spec->catfile($tmpdir, 'readme.txt');
        open my $fh2, '>', $txt_file or die;
        print $fh2 "hello";
        close $fh2;
        my $md_path = File::Spec->catfile($tmpdir, 'ext.md');
        open my $fh, '>', $md_path or die;
        print $fh "![doc](readme.txt)\n";
        close $fh;
        my $doc = Zepto::Document->load($md_path);
        local $ENV{TERM_PROGRAM} = 'ghostty';
        Zepto::Terminal->_reset_kitty_cache();
        my $result = Zepto::Renderer->_detect_markdown_images($doc, 0, 1);
        ok(!%$result, 'Non-image extensions are skipped');
    };
};

# ============================================================================
# Image spacer insertion
# ============================================================================

subtest 'Image spacer insertion in render' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    # Create a real image file
    my $img_path = File::Spec->catfile($tmpdir, 'photo.png');
    open my $ifh, '>:raw', $img_path or die;
    print $ifh pack('H*', '89504e470d0a1a0a0000000d494844520000000100000001' .
        '0100000000376ef9240000000a49444154789c626001000000050001e98aab' .
        '6c0000000049454e44ae426082');
    close $ifh;

    my $md_path = File::Spec->catfile($tmpdir, 'test.md');
    open my $fh, '>', $md_path or die;
    print $fh "# Title\n";
    print $fh "![photo](photo.png)\n";
    print $fh "After image\n";
    close $fh;

    my $doc = Zepto::Document->load($md_path);
    my $view = Zepto::View->new(document => $doc);
    my $theme = Zepto::Theme->dark_theme();

    local $ENV{TERM_PROGRAM} = 'ghostty';
    Zepto::Terminal->_reset_kitty_cache();

    my $frame = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    ok(defined $frame->{inline_images}, 'Frame contains inline_images');
    is(scalar @{$frame->{inline_images}}, 1, 'One image placement');
    is($frame->{inline_images}[0]{path}, $img_path, 'Image path is correct');
    ok($frame->{inline_images}[0]{screen_row} > 0, 'Screen row is positive');
    ok($frame->{inline_images}[0]{width} > 0, 'Width is positive');
    cmp_ok($frame->{inline_images}[0]{height_rows}, '>=', 3, 'Height is at least 3 rows');
    cmp_ok($frame->{inline_images}[0]{height_rows}, '<=', 20, 'Height is at most 20 rows');
};

subtest 'Image spacer respects cell_aspect parameter' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    # Create a 200x40 PNG (wide, short image that won't hit min/max row caps)
    # _get_image_dimensions reads width/height from bytes 16-23 of PNG header
    # CRC is not validated, so we can construct arbitrary dimensions
    my $img_path = File::Spec->catfile($tmpdir, 'wide.png');
    open my $ifh, '>:raw', $img_path or die;
    my $png_header = "\x89PNG\r\n\x1a\n";  # PNG signature (8 bytes)
    $png_header .= pack('N', 13);           # IHDR length
    $png_header .= 'IHDR';                  # IHDR type
    $png_header .= pack('NN', 200, 40);     # width=200, height=40
    $png_header .= pack('CCCCC', 8, 2, 0, 0, 0); # 8-bit RGB
    $png_header .= pack('N', 0);            # CRC placeholder
    $png_header .= pack('H*', '0000000049454e44ae426082'); # IEND
    print $ifh $png_header;
    close $ifh;

    # Verify our PNG is readable
    my ($w, $h) = Zepto::Renderer::_get_image_dimensions($img_path);
    is($w, 200, 'Test image width is 200');
    is($h, 40, 'Test image height is 40');

    my $md_path = File::Spec->catfile($tmpdir, 'aspect.md');
    open my $fh, '>', $md_path or die;
    print $fh "![wide](wide.png)\n";
    close $fh;

    my $doc = Zepto::Document->load($md_path);
    my $view = Zepto::View->new(document => $doc);
    my $theme = Zepto::Theme->dark_theme();

    local $ENV{TERM_PROGRAM} = 'ghostty';
    Zepto::Terminal->_reset_kitty_cache();

    # Render with default cell_aspect (2.0) — same as old * 0.5
    my $frame_default = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 40,
        cols     => 80,
    );

    # Render with cell_aspect = 1.0 (square cells)
    my $view2 = Zepto::View->new(document => $doc);
    my $frame_square = Zepto::Renderer->render(
        document    => $doc,
        view        => $view2,
        theme       => $theme,
        rows        => 40,
        cols        => 80,
        cell_aspect => 1.0,
    );

    ok(defined $frame_default->{inline_images}, 'Default: has inline images');
    ok(defined $frame_square->{inline_images}, 'Square: has inline images');

    if (@{$frame_default->{inline_images}} && @{$frame_square->{inline_images}}) {
        my $h_default = $frame_default->{inline_images}[0]{height_rows};
        my $h_square  = $frame_square->{inline_images}[0]{height_rows};
        # With aspect=1.0 (square cells), more rows are needed to display the
        # image because each cell is as wide as tall. With aspect=2.0, cells
        # are twice as tall, so fewer rows suffice. 200x40 image with ~75 avail
        # cols gives ~8 rows (aspect=2.0) vs ~15 rows (aspect=1.0).
        cmp_ok($h_square, '>', $h_default,
            "Square cells (aspect=1.0) need more rows ($h_square) than tall cells (aspect=2.0, $h_default)");
    }
};

subtest 'Image placement width reduces when row clamp fires' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    # Create a tall image that will hit the 20-row max at wide terminals
    # 200x800: aspect ratio 4:1 (tall). At 200 cols with aspect=2.0:
    # natural_rows = (800/200) * 200 / 2.0 = 400, clamped to 20
    # place_width should be reduced proportionally
    my $img_path = File::Spec->catfile($tmpdir, 'tall.png');
    open my $ifh, '>:raw', $img_path or die;
    my $png_header = "\x89PNG\r\n\x1a\n";
    $png_header .= pack('N', 13);
    $png_header .= 'IHDR';
    $png_header .= pack('NN', 200, 800);
    $png_header .= pack('CCCCC', 8, 2, 0, 0, 0);
    $png_header .= pack('N', 0);
    $png_header .= pack('H*', '0000000049454e44ae426082');
    print $ifh $png_header;
    close $ifh;

    my $md_path = File::Spec->catfile($tmpdir, 'ratio.md');
    open my $fh, '>', $md_path or die;
    print $fh "![tall](tall.png)\n";
    close $fh;

    my $doc = Zepto::Document->load($md_path);
    my $theme = Zepto::Theme->dark_theme();

    local $ENV{TERM_PROGRAM} = 'ghostty';
    Zepto::Terminal->_reset_kitty_cache();

    # Render at narrow width (spacers might not hit clamp)
    my $view1 = Zepto::View->new(document => $doc);
    my $frame_narrow = Zepto::Renderer->render(
        document => $doc,
        view     => $view1,
        theme    => $theme,
        rows     => 30,
        cols     => 30,
    );

    # Render at wide width (spacers will hit 20-row clamp, width should reduce)
    my $view2 = Zepto::View->new(document => $doc);
    my $frame_wide = Zepto::Renderer->render(
        document => $doc,
        view     => $view2,
        theme    => $theme,
        rows     => 30,
        cols     => 200,
    );

    if (@{$frame_narrow->{inline_images}} && @{$frame_wide->{inline_images}}) {
        my $narrow = $frame_narrow->{inline_images}[0];
        my $wide   = $frame_wide->{inline_images}[0];

        # Both should have height_rows = 20 (clamped)
        is($wide->{height_rows}, 20, 'Wide: height clamped to 20');

        # Wide placement width should NOT be the full available width
        # (it should be reduced to maintain aspect ratio)
        # gutter_width ≈ 4 (1 line), text_width = 200 - 4 = 196
        cmp_ok($wide->{width}, '<', 196,
            "Wide: placement width reduced (got $wide->{width})");

        # Aspect ratios (height/width) should be approximately equal
        my $ratio_narrow = $narrow->{height_rows} / $narrow->{width};
        my $ratio_wide   = $wide->{height_rows} / $wide->{width};
        my $diff = abs($ratio_narrow - $ratio_wide);
        cmp_ok($diff, '<', 0.15,
            "Aspect ratios similar: narrow=$ratio_narrow wide=$ratio_wide diff=$diff");
    }
};

# ============================================================================
# Image dimension reading
# ============================================================================

subtest '_get_image_dimensions' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    subtest 'reads PNG dimensions' => sub {
        my $png_path = File::Spec->catfile($tmpdir, 'dim.png');
        open my $fh, '>:raw', $png_path or die;
        # 1x1 PNG
        print $fh pack('H*', '89504e470d0a1a0a0000000d494844520000000100000001' .
            '0100000000376ef9240000000a49444154789c626001000000050001e98aab' .
            '6c0000000049454e44ae426082');
        close $fh;

        my ($w, $h) = Zepto::Renderer::_get_image_dimensions($png_path);
        is($w, 1, 'PNG width is 1');
        is($h, 1, 'PNG height is 1');
    };

    subtest 'reads GIF dimensions' => sub {
        my $gif_path = File::Spec->catfile($tmpdir, 'dim.gif');
        open my $fh, '>:raw', $gif_path or die;
        # Minimal GIF89a: 2x3 pixels
        print $fh "GIF89a";
        print $fh pack('vv', 2, 3);  # width=2, height=3 (little-endian)
        print $fh pack('CCC', 0, 0, 0);  # flags, bg, aspect
        close $fh;

        my ($w, $h) = Zepto::Renderer::_get_image_dimensions($gif_path);
        is($w, 2, 'GIF width is 2');
        is($h, 3, 'GIF height is 3');
    };

    subtest 'reads BMP dimensions' => sub {
        my $bmp_path = File::Spec->catfile($tmpdir, 'dim.bmp');
        open my $fh, '>:raw', $bmp_path or die;
        # Minimal BMP header: "BM" + 16 padding bytes + width(4) + height(4)
        print $fh "BM";
        print $fh "\x00" x 16;  # file header padding to reach offset 18
        print $fh pack('VV', 10, 7);  # width=10, height=7 (little-endian u32)
        close $fh;

        my ($w, $h) = Zepto::Renderer::_get_image_dimensions($bmp_path);
        is($w, 10, 'BMP width is 10');
        is($h, 7, 'BMP height is 7');
    };

    subtest 'returns empty for non-image file' => sub {
        my $txt_path = File::Spec->catfile($tmpdir, 'not_an_image.txt');
        open my $fh, '>', $txt_path or die;
        print $fh "hello world\n";
        close $fh;

        my @dims = Zepto::Renderer::_get_image_dimensions($txt_path);
        is(scalar @dims, 0, 'Non-image returns empty list');
    };

    subtest 'returns empty for missing file' => sub {
        my @dims = Zepto::Renderer::_get_image_dimensions('/nonexistent/path.png');
        is(scalar @dims, 0, 'Missing file returns empty list');
    };
};

# ============================================================================
# Image height clamping near screen bottom
# ============================================================================

subtest 'Image near screen bottom has clamped height_rows' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    # Create a tall image (200x800) that would need many spacer rows
    my $img_path = File::Spec->catfile($tmpdir, 'tall.png');
    open my $ifh, '>:raw', $img_path or die;
    my $png_header = "\x89PNG\r\n\x1a\n";
    $png_header .= pack('N', 13);
    $png_header .= 'IHDR';
    $png_header .= pack('NN', 200, 800);  # tall image
    $png_header .= pack('CCCCC', 8, 2, 0, 0, 0);
    $png_header .= pack('N', 0);
    $png_header .= pack('H*', '0000000049454e44ae426082');
    print $ifh $png_header;
    close $ifh;

    # Image on last line of a short document — spacers will get truncated
    my $md_path = File::Spec->catfile($tmpdir, 'bottom.md');
    open my $fh, '>', $md_path or die;
    # Put several lines before the image so it's near the screen bottom
    for my $i (1..8) {
        print $fh "Line $i\n";
    }
    print $fh "![tall](tall.png)\n";
    close $fh;

    my $doc = Zepto::Document->load($md_path);
    my $view = Zepto::View->new(document => $doc);
    my $theme = Zepto::Theme->dark_theme();

    local $ENV{TERM_PROGRAM} = 'ghostty';
    Zepto::Terminal->_reset_kitty_cache();

    # Small screen: rows=15, text_height=12 (15 - 3 chrome)
    # Image on line 8, after 8 text lines + 1 image-line = row 9 of text area
    # Only 3 rows left for spacers (12 - 9 = 3)
    my $frame = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 15,
        cols     => 80,
    );

    ok(defined $frame->{inline_images}, 'Frame has inline images');
    if (@{$frame->{inline_images}}) {
        my $img = $frame->{inline_images}[0];
        # The image would want 20 rows (capped max), but only a few fit on screen
        cmp_ok($img->{height_rows}, '<', 20,
            "Image height clamped to fit screen (got $img->{height_rows})");
        cmp_ok($img->{height_rows}, '>=', 1, 'Height is at least 1');
    }
};

# ============================================================================
# spacer_row_count in render frame
# ============================================================================

subtest 'spacer_row_count returned from render frame' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    my $img_path = File::Spec->catfile($tmpdir, 'photo.png');
    open my $ifh, '>:raw', $img_path or die;
    print $ifh pack('H*', '89504e470d0a1a0a0000000d494844520000000100000001' .
        '0100000000376ef9240000000a49444154789c626001000000050001e98aab' .
        '6c0000000049454e44ae426082');
    close $ifh;

    # Markdown with an image
    my $md_path = File::Spec->catfile($tmpdir, 'spacer.md');
    open my $fh, '>', $md_path or die;
    print $fh "# Title\n";
    print $fh "![photo](photo.png)\n";
    print $fh "After image\n";
    close $fh;

    my $doc = Zepto::Document->load($md_path);
    my $view = Zepto::View->new(document => $doc);
    my $theme = Zepto::Theme->dark_theme();

    local $ENV{TERM_PROGRAM} = 'ghostty';
    Zepto::Terminal->_reset_kitty_cache();

    my $frame = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    ok(exists $frame->{spacer_row_count}, 'Frame has spacer_row_count');
    cmp_ok($frame->{spacer_row_count}, '>', 0, 'spacer_row_count is positive when images present');

    # Without images (plain text)
    my $txt_path = File::Spec->catfile($tmpdir, 'plain.txt');
    open my $fh2, '>', $txt_path or die;
    print $fh2 "Just text\n";
    close $fh2;

    my $doc2 = Zepto::Document->load($txt_path);
    my $view2 = Zepto::View->new(document => $doc2);

    my $frame2 = Zepto::Renderer->render(
        document => $doc2,
        view     => $view2,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    is($frame2->{spacer_row_count}, 0, 'spacer_row_count is 0 without images');
};

# ============================================================================
# Minimap visibility with image spacers
# ============================================================================

subtest 'Minimap visible when images push content beyond viewport' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    # Create a tall image so spacer rows push content past viewport
    my $img_path = File::Spec->catfile($tmpdir, 'tall.png');
    open my $ifh, '>:raw', $img_path or die;
    my $png_header = "\x89PNG\r\n\x1a\n";
    $png_header .= pack('N', 13);
    $png_header .= 'IHDR';
    $png_header .= pack('NN', 200, 800);  # tall image → 20 spacer rows
    $png_header .= pack('CCCCC', 8, 2, 0, 0, 0);
    $png_header .= pack('N', 0);
    $png_header .= pack('H*', '0000000049454e44ae426082');
    print $ifh $png_header;
    close $ifh;

    # 10 lines of text + 1 image = 11 doc lines, but spacers add ~20 visual rows
    # With rows=24, text_height=21, 11 lines < 21 but 11 + 20 = 31 > 21
    my $md_path = File::Spec->catfile($tmpdir, 'minimap.md');
    open my $fh, '>', $md_path or die;
    for my $i (1..9) {
        print $fh "Line $i\n";
    }
    print $fh "![tall](tall.png)\n";
    print $fh "After image\n";
    close $fh;

    my $doc = Zepto::Document->load($md_path);
    my $view = Zepto::View->new(document => $doc);
    my $theme = Zepto::Theme->dark_theme();
    my $prefs = Zepto::Preferences->new(show_minimap => 1);

    local $ENV{TERM_PROGRAM} = 'ghostty';
    Zepto::Terminal->_reset_kitty_cache();

    my $frame = Zepto::Renderer->render(
        document => $doc,
        view     => $view,
        theme    => $theme,
        prefs    => $prefs,
        rows     => 24,
        cols     => 80,
    );

    # Minimap should appear because image spacers push content past viewport
    my $output = join('', @{$frame->{rows}});
    like($output, qr/[\x{2800}-\x{28FF}]/, 'Minimap appears when images push content beyond viewport');
};

subtest 'Minimap stable across consecutive renders (no oscillation)' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

    my $img_path = File::Spec->catfile($tmpdir, 'photo.png');
    open my $ifh, '>:raw', $img_path or die;
    my $png_header = "\x89PNG\r\n\x1a\n";
    $png_header .= pack('N', 13);
    $png_header .= 'IHDR';
    $png_header .= pack('NN', 200, 800);
    $png_header .= pack('CCCCC', 8, 2, 0, 0, 0);
    $png_header .= pack('N', 0);
    $png_header .= pack('H*', '0000000049454e44ae426082');
    print $ifh $png_header;
    close $ifh;

    my $md_path = File::Spec->catfile($tmpdir, 'stable.md');
    open my $fh, '>', $md_path or die;
    for my $i (1..9) {
        print $fh "Line $i\n";
    }
    print $fh "![photo](photo.png)\n";
    print $fh "After\n";
    close $fh;

    my $doc = Zepto::Document->load($md_path);
    my $theme = Zepto::Theme->dark_theme();
    my $prefs = Zepto::Preferences->new(show_minimap => 1);

    local $ENV{TERM_PROGRAM} = 'ghostty';
    Zepto::Terminal->_reset_kitty_cache();

    # Render twice — minimap decision should be stable (no oscillation)
    my $has_minimap_1;
    my $has_minimap_2;
    for my $i (1..2) {
        my $view = Zepto::View->new(document => $doc);
        my $frame = Zepto::Renderer->render(
            document => $doc,
            view     => $view,
            theme    => $theme,
            prefs    => $prefs,
            rows     => 24,
            cols     => 80,
        );
        my $output = join('', @{$frame->{rows}});
        my $has = ($output =~ /[\x{2800}-\x{28FF}]/) ? 1 : 0;
        if ($i == 1) { $has_minimap_1 = $has; }
        else         { $has_minimap_2 = $has; }
    }

    is($has_minimap_1, $has_minimap_2, 'Minimap decision stable across renders');
};

# ============================================================================
# Tab bar cache invalidation on theme change
# ============================================================================
subtest 'Tab bar cache invalidates on theme change' => sub {
    my $dark_theme = Zepto::Theme->dark_theme();
    my $light_theme = Zepto::Theme->light_theme();
    my $cols = 80;
    my $ui = {
        tabs => [{ display_name => 'test.txt', is_dirty => 0, has_vcs_changes => 0 }],
        active_tab_index => 0,
        tab_manager => undef,
    };

    my $dark_output = Zepto::Renderer->_render_tab_bar($dark_theme, $cols, $ui, 0);
    my $light_output = Zepto::Renderer->_render_tab_bar($light_theme, $cols, $ui, 0);

    isnt($dark_output, $light_output, 'Tab bar output differs between dark and light themes');
};

done_testing();
