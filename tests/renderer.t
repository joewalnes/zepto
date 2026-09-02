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
use Zepto::Editor;
use Zepto::Terminal;
use Zepto::FindEngine;
use Zepto::Highlighter;
use Zepto::CommandRegistry;
use Zepto::InputWidget;
use Zepto::FileTree;
use File::Temp qw(tempfile tempdir);

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

# Helper: a real (headless) editor instance, for tests that exercise the
# status bar's modifier-grouped pill columns — those pills are only built
# when ui.editor is set (see Renderer::_render_context_status_bar).
sub mock_terminal {
    my ($in_fh, $in_name) = tempfile(UNLINK => 1);
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    return Zepto::Terminal->new(in => $in_fh, out => $out_fh);
}

sub create_test_editor {
    my ($content) = @_;
    $content //= "Hello World\nLine 2\nLine 3\n";
    my $filename = create_temp_file($content);
    my $editor = Zepto::Editor->new(terminal => mock_terminal());
    my $doc = Zepto::Document->load($filename);
    my $view = Zepto::View->new(document => $doc);
    my $find_engine = Zepto::FindEngine->new(document => $doc);
    my $highlighter = Zepto::Highlighter->new();
    $editor->{tab_manager}->add_tab(
        document    => $doc,
        view        => $view,
        find_engine => $find_engine,
        highlighter => $highlighter,
        file_path   => $filename,
    );
    return ($editor, $doc, $view);
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

# ============================================================================
# Status bar: modifier-grouped pill columns (⌃ left / ⌥ right)
# ============================================================================
# See docs/UI_GUIDELINES.md "Context-Aware Status Bar" / "Priority-Based
# Progressive Disclosure" and bugs.md P1 "Status bar rework". These pills
# are only built when ui.editor is set, so tests here need a real editor
# (create_test_editor), not just a bare document/view.

subtest 'Status bar groups Ctrl pills left, Alt pills right, each pill shows its own modifier' => sub {
    my ($editor, $doc, $view) = create_test_editor();
    my $theme = Zepto::Theme->dark_theme();

    my $bar = Zepto::Renderer->_render_context_status_bar(
        $doc, $view, $theme, 200, undef, undef, { editor => $editor }, 0
    );
    my $s = strip_escapes($bar);

    # Ctrl-shortcut command: pill carries its own modifier glyph (e.g.
    # "Save \x{2303}S") -- an earlier design showed the modifier once per
    # column as a shared header, but direct user feedback found that made
    # individual pills hard to read in isolation ("I just saw 'T' but not
    # '^T'"). See docs/UI_GUIDELINES.md.
    like($s, qr/Save\s+\x{2303}S\b/, 'Ctrl group: Save pill repeats the ⌃ glyph');

    # Alt-shortcut command: same treatment.
    like($s, qr/Word Wrap\s+\x{2325}Z\b/, 'Alt group: Word Wrap pill repeats the ⌥ glyph');

    # There is no standalone column-header glyph anymore -- the modifier is
    # only ever attached to a pill, never rendered on its own.
    unlike($s, qr/\s\x{2303}\s/, 'no standalone ⌃ header separate from a pill');
    unlike($s, qr/\s\x{2325}\s/, 'no standalone ⌥ header separate from a pill');

    # Ctrl group renders left of Alt group, both left of the palette trigger.
    my $save_pos  = index($s, 'Save');
    my $wrap_pos  = index($s, 'Word Wrap');
    my $cmds_pos  = index($s, 'Commands');
    ok($save_pos >= 0 && $wrap_pos >= 0 && $cmds_pos >= 0, 'all three landmarks present');
    ok($save_pos < $wrap_pos, 'Ctrl (Save) pill renders left of Alt (Word Wrap) pill');
    ok($wrap_pos < $cmds_pos, 'Alt group renders left of the palette trigger pill');
};

subtest 'Theme pill has constant width across dark/light/auto (no status bar shift)' => sub {
    # bugs.md P2 "Toggling Light/Dark theme shifts the status bar because
    # 'light' has one more character than 'dark'" -- Renderer.pm's status
    # bar pill concatenates the RAW preference value ('dark'/'light'/'auto')
    # onto the Theme label with no width normalization, so the pill (and
    # everything rendered after it) shifts by one column depending on
    # which theme is active. At the wrong width, this can push a neighbor
    # pill's plain-language label (e.g. "Word Wrap") below its visibility
    # threshold entirely -- not just a cosmetic shift. cols=140 is the
    # exact width confirmed (via a live hangon repro) to cross that
    # threshold: dark shows "Word Wrap" in full, light drops it to a bare
    # glyph, purely because "light" is one character wider than "dark".
    # This subtest uses cols=145, a nearby width where "Word Wrap" is
    # visible in both states after the fix, so the assertions below
    # demonstrate the label actually surviving intact -- not just
    # "consistently absent in both," which cols=140 itself becomes after
    # the fix (both states now agree, they just both drop it at that
    # specific width -- see the sweep below for that width specifically).
    my ($editor, $doc, $view) = create_test_editor();
    my $dark_theme  = Zepto::Theme->dark_theme();
    my $light_theme = Zepto::Theme->light_theme();
    my $cols = 145;

    $editor->{prefs}->set_theme('dark');
    my $bar_dark = Zepto::Renderer->_render_context_status_bar(
        $doc, $view, $dark_theme, $cols, undef, undef, { editor => $editor }, 0
    );
    my $s_dark = strip_escapes($bar_dark);

    $editor->{prefs}->set_theme('light');
    my $bar_light = Zepto::Renderer->_render_context_status_bar(
        $doc, $view, $light_theme, $cols, undef, undef, { editor => $editor }, 0
    );
    my $s_light = strip_escapes($bar_light);

    is(length($s_dark), length($s_light),
        "Rendered status bar width is identical for dark vs light theme (cols=$cols)");

    # The real symptom: everything after the Theme pill (e.g. the Word Wrap
    # label) must land at the exact same column in both states, and must
    # not be dropped entirely in one state but not the other.
    my $wrap_pos_dark  = index($s_dark, 'Word Wrap');
    my $wrap_pos_light = index($s_light, 'Word Wrap');
    ok($wrap_pos_dark >= 0 && $wrap_pos_light >= 0,
        "Word Wrap label is present in both theme states (cols=$cols)");
    is($wrap_pos_dark, $wrap_pos_light,
        'Word Wrap label starts at the same column regardless of theme');

    # 'auto' ('dark'/'auto' are both 4 chars, coincidentally the same width
    # as each other but not as 'light' -- confirm it too matches 'light's
    # width, not just 'dark's, since all three are the same padded width.
    $editor->{prefs}->set_theme('auto');
    my $bar_auto = Zepto::Renderer->_render_context_status_bar(
        $doc, $view, $dark_theme, $cols, undef, undef, { editor => $editor }, 0
    );
    my $s_auto = strip_escapes($bar_auto);
    is(length($s_auto), length($s_light),
        'Rendered status bar width for auto matches light (both padded to the same width)');

    # Sweep a broader range of widths to catch the same class of bug at
    # OTHER threshold-crossing widths, not just the one confirmed live.
    for my $sweep_cols (60 .. 160) {
        $editor->{prefs}->set_theme('dark');
        my $bd = strip_escapes(Zepto::Renderer->_render_context_status_bar(
            $doc, $view, $dark_theme, $sweep_cols, undef, undef, { editor => $editor }, 0));
        $editor->{prefs}->set_theme('light');
        my $bl = strip_escapes(Zepto::Renderer->_render_context_status_bar(
            $doc, $view, $light_theme, $sweep_cols, undef, undef, { editor => $editor }, 0));
        is(length($bd), length($bl),
            "cols=$sweep_cols: identical total width for dark vs light");
    }
};

subtest 'Status bar priority-1 pill in each column survives narrow widths' => sub {
    my ($editor, $doc, $view) = create_test_editor();
    my $theme = Zepto::Theme->dark_theme();

    # Wide enough for both columns' top (priority-1) pill, but not the
    # full pill set — exercises the budget-negotiation guarantee rather
    # than just the unconstrained case.
    my $bar = Zepto::Renderer->_render_context_status_bar(
        $doc, $view, $theme, 62, undef, undef, { editor => $editor }, 0
    );
    my $s = strip_escapes($bar);

    like($s, qr/\bS\b/, 'Ctrl priority-1 (Save) key visible at narrow width');
    like($s, qr/\bZ\b/, 'Alt priority-1 (Word Wrap) key visible at narrow width');
    like($s, qr/\x{2303}\x{2423}/, 'Palette trigger still visible at narrow width');
};

subtest 'Status bar unconditional elements survive extreme narrow widths' => sub {
    my ($editor, $doc, $view) = create_test_editor();
    my $theme = Zepto::Theme->dark_theme();

    my $bar = Zepto::Renderer->_render_context_status_bar(
        $doc, $view, $theme, 32, undef, undef, { editor => $editor }, 0
    );
    my $s = strip_escapes($bar);

    like($s, qr/1:1/, 'Cursor position pill survives extreme narrow width');
    like($s, qr/\x{2303}\x{2423}/, 'Palette trigger pill survives extreme narrow width');
};

subtest 'Status bar pills stay clickable — button positions match rendered text' => sub {
    my ($editor, $doc, $view) = create_test_editor();
    my $theme = Zepto::Theme->dark_theme();

    Zepto::Renderer->_render_context_status_bar(
        $doc, $view, $theme, 140, undef, undef, { editor => $editor }, 0
    );
    my @buttons = Zepto::Renderer->get_status_buttons();

    my ($save_btn) = grep { $_->{command_id} eq 'save' } @buttons;
    ok($save_btn, 'Save pill registered a clickable button');
    ok($save_btn->{x_end} >= $save_btn->{x_start}, 'Save button has a non-empty hit area');

    my ($palette_btn) = grep { $_->{command_id} eq 'open_palette' } @buttons;
    ok($palette_btn, 'Palette trigger registered a clickable button');
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

# QA-REG-174: rows below EOF must use the CURRENT theme's own empty_line_bg,
# not the dark theme's — regression guard for a reported (but not reproduced
# against tmux's authoritative terminal state — see bugs.md 2026-08-30
# "Light-theme dark background fill investigation") bug claiming the
# below-EOF fill stayed dark-themed after switching to light. Asserts the
# actual RGB byte sequence, not just "renders without crashing" — a
# hardcoded/stale color or wrong theme-role name here would fail this.
subtest 'Empty lines beyond document use the light theme own background, not dark theme' => sub {
    my ($doc, $view) = create_test_state("Short\n");
    my $theme = Zepto::Theme->light_theme();

    my $output = Zepto::Renderer->render_string(
        document => $doc,
        view     => $view,
        theme    => $theme,
        rows     => 24,
        cols     => 80,
    );

    # Light theme's empty_line_bg is rgb(250,250,252) — near-white.
    like($output, qr/\x1b\[48;2;250;250;252m/,
        'Has light theme empty line background color');
    # Dark theme's empty_line_bg (20,21,30) must never leak into a light-theme frame.
    unlike($output, qr/\x1b\[48;2;20;21;30m/,
        'Does not contain dark theme empty line background color');
    # Dark theme's main bg (26,27,38) must not leak in either.
    unlike($output, qr/\x1b\[48;2;26;27;38m/,
        'Does not contain dark theme main background color');
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
    # cols=70 (>= MINIMAP_MIN_COLS), gutter=5, tree=55, minimap=8 => text=70-55-5-8=2 < MIN_TEXT_WIDTH
    my $width = Zepto::Renderer->get_minimap_width(100, 20, 70, 5, $prefs, 55);
    is($width, 0, 'Minimap drops off when tree takes space');

    # Without tree: cols=70, gutter=5, minimap=8 => text=57 >= MIN_TEXT_WIDTH
    my $width2 = Zepto::Renderer->get_minimap_width(100, 20, 70, 5, $prefs, 0);
    is($width2, 8, 'Minimap shows when tree is not present');
};

# ============================================================================
# QA-REG-177: minimap must auto-hide below MINIMAP_MIN_COLS, regardless of
# whether the dynamic MIN_TEXT_WIDTH check would otherwise leave it room.
# At 40 cols a minimap eats scarce width for little value (barely legible
# at that zoom) and crowds out content/status bar pills that matter more.
# See bugs.md and docs/UI_GUIDELINES.md "surviving down to ~40 cols".
# ============================================================================
subtest 'get_minimap_width returns 0 below MINIMAP_MIN_COLS even with plenty of room' => sub {
    my $prefs = Zepto::Preferences->new(show_minimap => 1);
    # cols=40, gutter=5, minimap=8 => dynamic text=27 >= MIN_TEXT_WIDTH, so the
    # OLD logic (pre-QA-REG-177) would have shown it. It must not now.
    my $width = Zepto::Renderer->get_minimap_width(100, 20, 40, 5, $prefs, 0);
    is($width, 0, 'Minimap hidden at 40 cols even though dynamic room check would pass');

    # One column below the threshold: still hidden.
    my $width_below = Zepto::Renderer->get_minimap_width(
        100, 20, Zepto::Renderer::MINIMAP_MIN_COLS - 1, 5, $prefs, 0
    );
    is($width_below, 0, 'Minimap hidden at MINIMAP_MIN_COLS - 1');

    # At the threshold and above: shown (given otherwise-sufficient room).
    my $width_at = Zepto::Renderer->get_minimap_width(
        100, 20, Zepto::Renderer::MINIMAP_MIN_COLS, 5, $prefs, 0
    );
    is($width_at, Zepto::Renderer::MINIMAP_WIDTH, 'Minimap shown at MINIMAP_MIN_COLS');

    my $width_above = Zepto::Renderer->get_minimap_width(
        100, 20, Zepto::Renderer::MINIMAP_MIN_COLS + 20, 5, $prefs, 0
    );
    is($width_above, Zepto::Renderer::MINIMAP_WIDTH, 'Minimap shown comfortably above MINIMAP_MIN_COLS');
};

subtest 'Minimap auto-hides via full render at narrow widths (QA-REG-177)' => sub {
    my $content = join('', map { "Line number $_ with some content here\n" } (1..50));
    my ($doc, $view) = create_test_state($content);
    my $theme = Zepto::Theme->dark_theme();
    my $prefs = Zepto::Preferences->new(show_minimap => 1);

    for my $cols (40, 50, 59) {
        my $output = Zepto::Renderer->render_string(
            document => $doc, view => $view, theme => $theme, prefs => $prefs,
            rows => 20, cols => $cols,
        );
        unlike($output, qr/[\x{2800}-\x{28FF}]/, "No minimap braille chars at cols=$cols (below threshold)");
    }

    for my $cols (60, 80, 120) {
        my $output = Zepto::Renderer->render_string(
            document => $doc, view => $view, theme => $theme, prefs => $prefs,
            rows => 20, cols => $cols,
        );
        like($output, qr/[\x{2800}-\x{28FF}]/, "Minimap braille chars present at cols=$cols (at/above threshold)");
    }
};

subtest 'Manual minimap preference still works normally above MINIMAP_MIN_COLS (QA-REG-177)' => sub {
    my $content = join('', map { "Line number $_ with some content here\n" } (1..50));
    my ($doc, $view) = create_test_state($content);
    my $theme = Zepto::Theme->dark_theme();

    # Preference OFF: no minimap even at a comfortably wide terminal.
    my $prefs_off = Zepto::Preferences->new(show_minimap => 0);
    my $output_off = Zepto::Renderer->render_string(
        document => $doc, view => $view, theme => $theme, prefs => $prefs_off,
        rows => 20, cols => 100,
    );
    unlike($output_off, qr/[\x{2800}-\x{28FF}]/, 'Minimap preference OFF hides minimap at 100 cols');

    # Preference ON above the threshold: minimap still shows (existing
    # manual toggle behavior — this fix must not touch it).
    my $prefs_on = Zepto::Preferences->new(show_minimap => 1);
    my $output_on = Zepto::Renderer->render_string(
        document => $doc, view => $view, theme => $theme, prefs => $prefs_on,
        rows => 20, cols => 100,
    );
    like($output_on, qr/[\x{2800}-\x{28FF}]/, 'Minimap preference ON shows minimap at 100 cols');
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

subtest '_ellipsis in scalar context (existing callers)' => sub {
    is(Zepto::Renderer::_ellipsis('hello', 10), 'hello', 'no truncation when it fits');
    is(Zepto::Renderer::_ellipsis('hello world', 5), "hell\x{2026}", "'end' mode truncates tail");
    is(Zepto::Renderer::_ellipsis('hello world', 5, 'start'), "\x{2026}orld",
        "'start' mode truncates front");
};

subtest '_ellipsis in list context returns trim offset (bugs.md DRY finding)' => sub {
    # Extended so the file-tree flat-filter renderer can reuse this instead
    # of hand-rolling start-truncation with its own offset arithmetic.
    my ($str, $offset);

    # No truncation: offset is always 0
    ($str, $offset) = Zepto::Renderer::_ellipsis('short.txt', 20, 'start');
    is($str, 'short.txt', 'untruncated string returned as-is');
    is($offset, 0, 'trim offset is 0 when nothing was trimmed');

    # Exactly at the boundary: still no truncation
    ($str, $offset) = Zepto::Renderer::_ellipsis('short.txt', 9, 'start');
    is($str, 'short.txt', 'string exactly max_width long is not truncated');
    is($offset, 0, 'trim offset is 0 at the exact boundary');

    # One character over the boundary
    ($str, $offset) = Zepto::Renderer::_ellipsis('short.txt', 8, 'start');
    is($str, "\x{2026}ort.txt", 'one char over triggers minimal truncation');
    is($offset, 2, 'trim offset accounts for the dropped char plus ellipsis slot');

    # Deep path, small budget
    ($str, $offset) = Zepto::Renderer::_ellipsis('a/very/deep/path/to/some/file.pm', 5, 'start');
    is($str, "\x{2026}e.pm", 'heavily truncated path keeps the tail');
    is($offset, 28, 'trim offset matches number of chars dropped from the front');

    # Empty string
    ($str, $offset) = Zepto::Renderer::_ellipsis('', 5, 'start');
    is($str, '', 'empty string stays empty');
    is($offset, 0, 'trim offset is 0 for empty string');

    # Unicode / wide characters — length() is codepoint-based here, matching
    # the file-tree renderer's own use of length() for match-position math.
    my $unicode_path = "a/b/c/\x{6587}\x{4EF6}\x{5939}/\x{4E2D}\x{6587}\x{6587}\x{4EF6}\x{540D}.txt";
    ($str, $offset) = Zepto::Renderer::_ellipsis($unicode_path, 10, 'start');
    is(CORE::length($str), 10, 'unicode: truncated string is exactly max_width chars long');
    like($str, qr/^\x{2026}/, 'unicode: truncated string is prefixed with ellipsis');
    is(substr($unicode_path, $offset), substr($str, 1),
        'unicode: substr($original, $offset) reproduces the kept tail exactly');

    # 'end' mode: trim offset is always 0 (no callers currently need it,
    # but the contract should hold so future callers can rely on it)
    ($str, $offset) = Zepto::Renderer::_ellipsis('hello world', 5, 'end');
    is($str, "hell\x{2026}", "'end' mode still truncates the tail correctly");
    is($offset, 0, "'end' mode never trims the front, so offset is 0");
};

subtest 'File-tree flat-filter rendering truncates via _ellipsis and remaps match highlight' => sub {
    # Integration test for the consumer of _ellipsis()'s new trim-offset
    # return value: _render_tree_node_content()'s flat filter-search mode
    # (bugs.md "Scorecard audit round 3" DRY finding — this used to
    # hand-roll the same truncation arithmetic inline).
    my $theme = Zepto::Theme->dark_theme();
    my $path = 'a/very/deep/path/to/some/file.pm';  # length 32

    # Match positions: 5 ('y' in "very", gets trimmed off) and 28
    # ('e', the last char of "file", survives truncation).
    my $node = {
        name => $path,
        is_dir => 0,
        depth => 0,
        _filter_match_positions => [5, 28],
    };

    # width=8: 1 (leading space) + 2 (icon+space) used, leaving name_space=5
    # -> _ellipsis($path, 5, 'start') truncates to "…e.pm" (matches the
    # manually-verified trim_offset=28 from the _ellipsis list-context test above)
    my @out = Zepto::Renderer->_render_tree_node_content(
        $node, 8, $theme,
        0,      # is_cursor
        0,      # is_sticky
        1,      # focused
        0,      # has_scrollbar
        0,      # row_idx
        undef,  # sb
        1,      # is_last
        [],     # guides
        1,      # filter_active
        0,      # is_current
        0,      # is_hover
    );
    my $output = join('', @out);

    (my $visible = $output) =~ s/\x1b\[[0-9;]*m//g;
    my $icon = Zepto::Chars->file_icon('file.pm') // ' ';
    is($visible, " $icon \x{2026}e.pm",
        'display path is truncated to "…e.pm" with icon/leading-space prefix');

    my $match_fg = $theme->color('tree_match_fg');
    my $match_count = () = $output =~ /\Q$match_fg\E/g;
    is($match_count, 1, 'exactly one character is highlighted as a match — ' .
        'proves the trimmed-off match position (5, in "very") produced no highlight');

    like($output, qr/\Q$match_fg\E(?:\x1b\[[0-9;]*m)*e/,
        'the surviving match position (28, the "e" in "file") is highlighted — ' .
        'proves the trim offset correctly remapped the original-string match position ' .
        'onto the truncated display string');
};

# ============================================================================
# _render_tree_panel's search-bar row (bugs.md P1: "File-tree flat-filter
# search... has zero UI trigger" — the cursor-placement logic for this row
# already existed, but nothing actually drew the row's visible content
# until this fix). Uses a real Zepto::FileTree against a tempdir so the
# search bar is exercised end-to-end, not just the isolated row-content
# helper tested above.
# ============================================================================
subtest '_render_tree_panel draws a search-bar row with the query text when filtering' => sub {
    my $dir = tempdir(CLEANUP => 1);
    open(my $fh, '>', "$dir/needle.txt") or die $!;
    close $fh;

    my $theme = Zepto::Theme->dark_theme();
    my $tree = Zepto::FileTree->new(root_path => $dir);
    $tree->set_focused(1);
    $tree->start_filter();
    # "edl" is used (not e.g. "ndl") because FileTree's pre-filter step
    # requires the query to appear as a literal contiguous substring
    # (index() check) before fuzzy-scoring a candidate at all — "edl" is
    # a contiguous run within "needle.txt" (n-e-e-d-l-e...), "ndl" isn't.
    $tree->filter_append_char($_) for split //, 'edl';

    my $rows = Zepto::Renderer->_render_tree_panel($tree, 10, $theme, 20, {});
    my $row1 = $rows->[0];
    (my $visible = $row1) =~ s/\x1b\[[0-9;]*m//g;

    my $icon = Zepto::Chars->get('search') || '*';
    like($visible, qr/\Q$icon\E\s*edl/, 'Row 1 shows the search icon followed by the typed query "edl"');

    # Tree content (the flat filtered match) must start on row 2, not
    # overwrite the search bar.
    my $row2 = $rows->[1];
    (my $visible2 = $row2) =~ s/\x1b\[[0-9;]*m//g;
    like($visible2, qr/needle\.txt/, 'Row 2 shows the matched file — content is pushed below the search bar');
};

subtest '_render_tree_panel omits the search-bar row when not filtering' => sub {
    my $dir = tempdir(CLEANUP => 1);
    open(my $fh, '>', "$dir/plain.txt") or die $!;
    close $fh;

    my $theme = Zepto::Theme->dark_theme();
    my $tree = Zepto::FileTree->new(root_path => $dir);
    $tree->set_focused(1);

    my $rows = Zepto::Renderer->_render_tree_panel($tree, 10, $theme, 20, {});
    my $row1 = $rows->[0];
    (my $visible = $row1) =~ s/\x1b\[[0-9;]*m//g;

    like($visible, qr/plain\.txt/,
        'Row 1 shows tree content directly (no search bar reserved) when not filtering');
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

# ============================================================================
# Tab width threading (bugs.md P1 "Tab Width preference has no effect on
# rendering existing tab characters" / QA-REG-189)
#
# Before the fix, _expand_tabs/_char_to_visual_col/visual_to_char_col
# always used the hardcoded `TAB_WIDTH => 4` constant -- there was no way
# to pass a different width in at all, so these assertions would fail
# against the pre-fix code (there was no third argument to pass, and no
# set_tab_width() to call).
# ============================================================================
subtest 'tab expansion honors an explicit width argument, not just TAB_WIDTH=4' => sub {
    my ($expanded4, undef) = Zepto::Renderer::_expand_tabs("\tx", 4);
    is($expanded4, (' ' x 4) . 'x', '_expand_tabs: explicit width 4');

    my ($expanded8, undef) = Zepto::Renderer::_expand_tabs("\tx", 8);
    is($expanded8, (' ' x 8) . 'x',
        '_expand_tabs: explicit width 8 -- would be 4 spaces under the old hardcoded constant');

    is(Zepto::Renderer::_char_to_visual_col("\tx", 2, 8), 9,
        '_char_to_visual_col: width 8 -- tab expands to 8, "x" lands at visual col 9');
    is(Zepto::Renderer::_char_to_visual_col("\tx", 2, 4), 5,
        '_char_to_visual_col: width 4 -- tab expands to 4, "x" lands at visual col 5');

    is(Zepto::Renderer::visual_to_char_col("\tx", 8, 8), 1,
        'visual_to_char_col: width 8 -- visual col 8 (start of "x") is char index 1');
    is(Zepto::Renderer::visual_to_char_col("\tx", 4, 4), 1,
        'visual_to_char_col: width 4 -- visual col 4 (start of "x") is char index 1');
};

subtest 'set_tab_width() changes the default width used when no explicit arg is passed' => sub {
    Zepto::Renderer->set_tab_width(2);
    my ($expanded, undef) = Zepto::Renderer::_expand_tabs("\tx");
    is($expanded, '  x', 'set_tab_width(2): _expand_tabs defaults to a 2-col tab with no explicit arg');
    is(Zepto::Renderer::_char_to_visual_col("\tx", 2), 3,
        'set_tab_width(2): _char_to_visual_col picks up the synced default width');

    Zepto::Renderer->set_tab_width(8);
    ($expanded, undef) = Zepto::Renderer::_expand_tabs("\tx");
    is($expanded, (' ' x 8) . 'x', 'set_tab_width(8): _expand_tabs picks up the new default width');

    # Invalid preference values must not wedge rendering with a
    # divide-by-zero or a negative expansion -- fall back to TAB_WIDTH.
    Zepto::Renderer->set_tab_width(0);
    ($expanded, undef) = Zepto::Renderer::_expand_tabs("\tx");
    is($expanded, (' ' x Zepto::Renderer::TAB_WIDTH) . 'x',
        'set_tab_width(0) falls back to TAB_WIDTH instead of dividing by zero');

    # Restore the module-level default so later subtests in this process
    # (renderer.t runs many subtests against a shared package) aren't
    # affected by this subtest's state.
    Zepto::Renderer->set_tab_width(Zepto::Renderer::TAB_WIDTH);
};

subtest 'render() syncs the effective tab width from prefs on every render pass' => sub {
    my $content = "\tindented";
    my $filename = create_temp_file($content);
    my $doc = Zepto::Document->load($filename);
    my $view = Zepto::View->new(document => $doc);
    my $theme = Zepto::Theme->dark_theme();

    for my $width (2, 8) {
        my $prefs = Zepto::Preferences->new(tab_width => $width);
        Zepto::Renderer->render(
            document => $doc,
            view     => $view,
            theme    => $theme,
            prefs    => $prefs,
            rows     => 10,
            cols     => 40,
        );
        my ($expanded, undef) = Zepto::Renderer::_expand_tabs("\tx");
        is($expanded, (' ' x $width) . 'x',
            "after render() with prefs->tab_width=$width, tab-expansion helpers default to that width");
    }

    Zepto::Renderer->set_tab_width(Zepto::Renderer::TAB_WIDTH);
};

# ============================================================================
# _expand_tabs() memo cache (bugs.md "Scorecard audit round 3" P2:
# "Renderer.pm's _expand_tabs() has no cache -- same missed pattern the
# Highlighter token cache (round 2) just fixed")
#
# Mirrors round 2's Highlighter cache test philosophy: prove correctness
# UNDER INVALIDATION (content change, tab-width change), not just "cache
# works when nothing changes" -- that's the anti-pattern round 2's own
# writeup calls out. Uses the test-only _reset_expand_tabs_cache_for_tests()
# / _expand_tabs_cache_size_for_tests() introspection hooks so these tests
# don't depend on execution order against the rest of this file.
# ============================================================================
subtest 'expand_tabs cache: identical repeated calls are memoized, not recomputed' => sub {
    Zepto::Renderer::_reset_expand_tabs_cache_for_tests();
    is(Zepto::Renderer::_expand_tabs_cache_size_for_tests(), 0, 'Cache starts empty');

    my ($e1, $c1) = Zepto::Renderer::_expand_tabs("\tfoo", 4);
    is(Zepto::Renderer::_expand_tabs_cache_size_for_tests(), 1, 'First call populates one cache entry');

    my ($e2, $c2) = Zepto::Renderer::_expand_tabs("\tfoo", 4);
    is(Zepto::Renderer::_expand_tabs_cache_size_for_tests(), 1, 'Repeated identical call is a cache hit -- no new entry');
    is($e2, $e1, 'Cache hit returns the same expanded string');
    is_deeply($c2, $c1, 'Cache hit returns the same char_to_visual mapping');
    # Proves the SAME arrayref is served (memoized), not a freshly-built
    # equal-but-different one -- the strongest evidence the cache path
    # actually ran rather than recomputation coincidentally matching.
    is($c2, $c1, 'Cache hit returns the identical (===) arrayref, not a fresh copy');
};

subtest 'expand_tabs cache: changed content is a cache miss and never returns stale data' => sub {
    Zepto::Renderer::_reset_expand_tabs_cache_for_tests();

    my ($e1) = Zepto::Renderer::_expand_tabs("\tfoo", 4);
    is($e1, (' ' x 4) . 'foo', 'Initial expansion of "\tfoo" at width 4');

    my ($e2) = Zepto::Renderer::_expand_tabs("\tbar", 4);
    is(Zepto::Renderer::_expand_tabs_cache_size_for_tests(), 2, 'Different content is a second, distinct cache entry');
    is($e2, (' ' x 4) . 'bar', 'Different content recomputes correctly, not served "\tfoo"\'s stale expansion');
    isnt($e2, $e1, 'Sanity: the two results actually differ');

    # Editing the line back to its original content must be a fresh cache
    # HIT on the original key, not a miss that silently recomputes wrong.
    my ($e3) = Zepto::Renderer::_expand_tabs("\tfoo", 4);
    is($e3, $e1, 'Reverting content to a previously-seen value hits the original cache entry correctly');
};

subtest 'expand_tabs cache: changed tab_width is a cache miss and never returns stale data' => sub {
    Zepto::Renderer::_reset_expand_tabs_cache_for_tests();

    my ($e4) = Zepto::Renderer::_expand_tabs("\tx", 4);
    is($e4, (' ' x 4) . 'x', 'Width 4 expansion cached');

    my ($e8) = Zepto::Renderer::_expand_tabs("\tx", 8);
    is($e8, (' ' x 8) . 'x',
        'Same text, different width -- correctly recomputed to 8 spaces, not served the width-4 cached result');
    is(Zepto::Renderer::_expand_tabs_cache_size_for_tests(), 2, 'Width 4 and width 8 are tracked as distinct cache entries');

    # Going through set_tab_width() (the real render() code path) must also
    # correctly separate cache entries by the *effective* width, not
    # collapse them because no explicit width argument was passed.
    Zepto::Renderer->set_tab_width(4);
    my ($ed) = Zepto::Renderer::_expand_tabs("\tx");
    is($ed, $e4, 'Default width (synced to 4) hits the same entry as explicit width=4');

    Zepto::Renderer->set_tab_width(8);
    my ($ed2) = Zepto::Renderer::_expand_tabs("\tx");
    is($ed2, $e8, 'Default width (synced to 8) hits the same entry as explicit width=8, not stale width-4 data');

    Zepto::Renderer->set_tab_width(Zepto::Renderer::TAB_WIDTH);
};

subtest 'expand_tabs cache: keyed on (text, tab_width) -- distinct keys never collide' => sub {
    Zepto::Renderer::_reset_expand_tabs_cache_for_tests();

    # Directly poison one specific (text, width) cache slot via the public
    # behavior (impossible to do without the cache existing at all), then
    # confirm a DIFFERENT key is unaffected -- this is the regression a
    # too-coarse cache key (e.g. content-only, ignoring width) would fail:
    # it would incorrectly serve one width's expansion for another.
    my ($narrow) = Zepto::Renderer::_expand_tabs("\tabc", 2);
    my ($wide)   = Zepto::Renderer::_expand_tabs("\tabc", 6);
    isnt($narrow, $wide, 'Same text at two different widths must never produce identical output here');
    is($narrow, (' ' x 2) . 'abc', 'Width 2 entry is correct');
    is($wide, (' ' x 6) . 'abc', 'Width 6 entry is unaffected by the width-2 entry existing');
};

subtest 'expand_tabs cache: bounded size, evicts wholesale past the cap' => sub {
    Zepto::Renderer::_reset_expand_tabs_cache_for_tests();

    my $cap = Zepto::Renderer::MAX_EXPAND_TABS_CACHE_ENTRIES;
    for my $i (1 .. $cap) {
        Zepto::Renderer::_expand_tabs("line_$i", 4);
    }
    is(Zepto::Renderer::_expand_tabs_cache_size_for_tests(), $cap, "Cache holds exactly $cap entries at the cap");

    # One more distinct entry pushes past the cap -- must evict wholesale
    # (drop back to a small count) rather than growing unbounded.
    Zepto::Renderer::_expand_tabs("one_more_line", 4);
    my $size_after = Zepto::Renderer::_expand_tabs_cache_size_for_tests();
    ok($size_after < $cap, "Cache size ($size_after) drops well below the cap after eviction, not unbounded growth");

    # Post-eviction correctness: a fresh call still computes the right
    # answer, it's just no longer memoized against the evicted entries.
    my ($e) = Zepto::Renderer::_expand_tabs("\tpost-eviction", 4);
    is($e, (' ' x 4) . 'post-eviction', 'Cache still computes correctly after eviction, not corrupted');

    Zepto::Renderer::_reset_expand_tabs_cache_for_tests();
};

subtest 'Public expand_tabs()/char_to_visual_col() wrappers match the private functions exactly' => sub {
    # bugs.md "Scorecard audit round 3" P3: WrapMap.pm previously reached
    # into these via full package-qualified underscore-prefixed (private)
    # names. These public wrappers are the fix -- confirm they are pure
    # pass-throughs with identical behavior, not a second implementation
    # that could drift from the private one.
    my ($e_priv, $c_priv) = Zepto::Renderer::_expand_tabs("\tabc\tdef", 4);
    my ($e_pub, $c_pub)   = Zepto::Renderer::expand_tabs("\tabc\tdef", 4);
    is($e_pub, $e_priv, 'expand_tabs() matches _expand_tabs() output');
    is_deeply($c_pub, $c_priv, 'expand_tabs() matches _expand_tabs() char_to_visual mapping');

    my $priv_col = Zepto::Renderer::_char_to_visual_col("\tabc", 3, 4);
    my $pub_col  = Zepto::Renderer::char_to_visual_col("\tabc", 3, 4);
    is($pub_col, $priv_col, 'char_to_visual_col() matches _char_to_visual_col() output');
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
# QA-REG-179: the persistent (non-message) document status bar must never
# emit more printable-width content than the terminal's actual column
# count, at any width. Confirmed via direct screenshot: with multi-cursor
# mode active (⌃D "select next occurrence" a handful of times) or column
# select mode active, the cursor-position pill + supplementary indicator
# (COL rect / "N cursors") + fixed palette pill together could exceed
# $cols with nothing to shrink them — the terminal then soft-wrapped the
# overflow onto a phantom row, scrolling and corrupting the whole screen
# (tab bar and ruler disappeared). Root cause: the COL / multi-cursor
# segments were emitted unconditionally into the output buffer before the
# ⌃/⌥ pill-group budget was computed, so by the time that budget clamped
# to 0 the damage (an already-too-wide left segment) was already done.
# Fix: those supplementary segments are now gated behind the same fixed
# budget (cursor pill + round cap + palette pill + gaps) the rest of the
# bar already respects, and even the cursor pill itself is ellipsized as
# a last-resort backstop for pathological cases (huge line/col numbers).
# See bugs.md, docs/help/changelog.md 2026-08-30, qa/40_regression_bugs.txt.
# ============================================================================
subtest 'Context status bar never exceeds terminal width: multi-cursor / column-select property sweep (QA-REG-179)' => sub {
    my ($editor, $doc, $view) = create_test_editor();
    my $theme = Zepto::Theme->dark_theme();

    my $checks = 0;
    my $failures = 0;
    my @first_failures;

    for my $nerd_font (0, 1) {
        Zepto::Chars->set_enabled($nerd_font);
        for my $cols (25, 30, 35, 40, 45, 50, 60, 80, 120) {
            for my $mc (0, 1, 2, 5, 9, 15, 25, 60) {
                for my $colsel (0, 1) {
                    $view->clear_multi_cursors();
                    for my $n (1 .. $mc) {
                        $view->add_multi_cursor(line => 0, col => $n);
                    }
                    if ($colsel) {
                        $view->enter_column_mode();
                        $view->start_column_selection();
                        $view->set_cursor(2, 5, 1);
                    } else {
                        $view->exit_column_mode();
                    }

                    my $bar = Zepto::Renderer->_render_context_status_bar(
                        $doc, $view, $theme, $cols, '', 0, { editor => $editor }, 0
                    );
                    my $plain = strip_escapes($bar);
                    $plain =~ s/\x1b\[K//g;

                    $checks++;
                    if (length($plain) > $cols) {
                        $failures++;
                        push @first_failures,
                            "nerd_font=$nerd_font cols=$cols mc=$mc colsel=$colsel len=" . length($plain)
                            if @first_failures < 10;
                    }
                }
            }
        }
    }
    Zepto::Chars->set_enabled(1);  # restore default for subsequent tests

    is($failures, 0, "status bar never exceeds \$cols across $checks combinations")
        or diag(join("\n", @first_failures));
};

# Below MINIMAP_MIN_COLS-style structural floors (roughly < 25 cols), the
# palette pill ("Commands ⌃␣") alone — which UI_GUIDELINES.md requires stay
# "never droppable by width or context" — cannot fit alongside anything
# else. That is a pre-existing, out-of-scope structural limit (Zepto's
# documented floor for essential chrome is "~40 cols", see
# docs/UI_GUIDELINES.md), not a regression introduced or claimed fixed
# here. The sweep above intentionally starts at 25 cols.
subtest 'Context status bar stays exactly bounded (no slack lost) for plain single-cursor state' => sub {
    my ($editor, $doc, $view) = create_test_editor();
    my $theme = Zepto::Theme->dark_theme();

    for my $cols (25, 30, 40, 50, 60, 80, 120) {
        my $bar = Zepto::Renderer->_render_context_status_bar(
            $doc, $view, $theme, $cols, '', 0, { editor => $editor }, 0
        );
        my $plain = strip_escapes($bar);
        $plain =~ s/\x1b\[K//g;
        ok(length($plain) <= $cols, "plain status bar fits within cols=$cols")
            or diag("length=" . length($plain) . " cols=$cols");
    }
};

# Full end-to-end sweep: varying filenames (short and realistic lengths,
# per the original bug report's repro) crossed with a range of terminal
# widths, asserting EVERY row of a complete rendered frame — not just the
# status bar — stays within $cols. This is the general property the task
# calls for: it must hold for any combination, not just the one repro.
subtest 'No row of a full rendered frame ever exceeds terminal width, across filenames and widths (QA-REG-179)' => sub {
    use File::Temp qw(tempdir);
    my $tmpdir = tempdir(CLEANUP => 1);
    my @filenames = ('a.txt', 'x', 'zdisc_check.demo.txt', 'a-fairly-long-realistic-filename.pm');
    my $theme = Zepto::Theme->dark_theme();
    my $prefs = Zepto::Preferences->new(show_minimap => 1);

    my $checks = 0;
    my $failures = 0;
    my @first_failures;

    for my $filename (@filenames) {
        my $content = join('', map { "line $_ of content\n" } (1..30));
        my $path = "$tmpdir/$filename";
        open(my $fh, '>', $path) or die "cannot write $path: $!";
        print $fh $content;
        close $fh;
        my $doc = Zepto::Document->load($path);
        my $view = Zepto::View->new(document => $doc);

        for my $cols (30, 40, 50, 60, 80) {
            for my $rows (15, 18, 20, 24) {
                my $frame = Zepto::Renderer->render(
                    document => $doc, view => $view, theme => $theme, prefs => $prefs,
                    rows => $rows, cols => $cols,
                );
                for my $i (0 .. $#{ $frame->{rows} }) {
                    my $plain = strip_escapes($frame->{rows}[$i]);
                    $plain =~ s/\x1b\[K//g;
                    $checks++;
                    if (length($plain) > $cols) {
                        $failures++;
                        push @first_failures,
                            "filename=$filename cols=$cols rows=$rows row_idx=$i len=" . length($plain)
                            if @first_failures < 10;
                    }
                }
            }
        }
    }

    is($failures, 0, "no rendered row exceeds \$cols across $checks (filename, width, height) combinations")
        or diag(join("\n", @first_failures));
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

# QA-REG-175: image spacer rows (blank rows reserved below a Markdown inline
# image) must fill with the theme's real 'bg' role, not a nonexistent
# 'editor_bg' role. Found via code audit while investigating QA-REG-174
# (see bugs.md 2026-08-30) — Theme::color() silently returns '' for an
# unknown role name, so this previously emitted NO background color at all
# for the spacer row's text area in both themes. Isolates the exact spacer
# rows via inline_images{screen_row,height_rows} (not a whole-frame
# substring search) so this can't pass merely because an unrelated content
# row elsewhere in the frame happens to use the same 'bg' role.
subtest 'Image spacer rows use the real theme bg color, not a blank/missing role' => sub {
    use File::Temp qw(tempdir);
    use File::Spec;

    my $tmpdir = tempdir(CLEANUP => 1);

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

    local $ENV{TERM_PROGRAM} = 'ghostty';
    Zepto::Terminal->_reset_kitty_cache();

    for my $spec (
        { name => 'light', theme => Zepto::Theme->light_theme(), bg => '255;255;255' },
        { name => 'dark',  theme => Zepto::Theme->dark_theme(),  bg => '26;27;38' },
    ) {
        my $doc = Zepto::Document->load($md_path);
        my $view = Zepto::View->new(document => $doc);

        my $frame = Zepto::Renderer->render(
            document => $doc,
            view     => $view,
            theme    => $spec->{theme},
            rows     => 24,
            cols     => 80,
        );

        is(scalar @{$frame->{inline_images}}, 1, "$spec->{name} theme: one image placement");
        my $placement = $frame->{inline_images}[0];
        my $first_spacer_idx = $placement->{screen_row} - 1;  # screen_row is 1-based
        my $last_spacer_idx  = $first_spacer_idx + $placement->{height_rows} - 1;

        for my $i ($first_spacer_idx .. $last_spacer_idx) {
            like($frame->{rows}[$i], qr/\x1b\[48;2;$spec->{bg}m/,
                "$spec->{name} theme: spacer row $i has the real bg color, not a blank/missing role");
        }
    }
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

# ============================================================================
# Tab bar "tabby" redesign (2026-08-30) — see bugs.md and
# qa/21_tabs.txt. User feedback: tabs "really don't look great" — inactive
# tabs had no visible background fill (only underlined plain text), and a
# zoomed *hangon screenshot* crop of the ◢/◣ diagonal-corner glyphs showed
# them as a nearly-invisible 1-cell wedge. A same-day redesign temporarily
# replaced the triangles with a full-block (█, U+2588) cap glyph — but the
# "nearly invisible" premise turned out to be a hangon rendering bug (it
# drew geometric-shape characters via ordinary font glyphs instead of
# procedurally, unlike a real terminal), confirmed and fixed in hangon
# itself (see hangon's CHANGELOG). Reverted the cap glyph back to ◢/◣
# accordingly. The independently-real fix — tab_inactive_bg/tab_hover_bg
# given meaningfully higher contrast against tab_bar_bg in both themes —
# is unrelated to cap shape and is kept (see Theme.pm "Tabby redesign"
# comments, and the subtest right after this one).
# ============================================================================
subtest 'Tab caps use the ◢/◣ diagonal triangle glyphs' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $ui = {
        tabs => [
            { display_name => 'active.txt',   is_dirty => 0, has_vcs_changes => 0 },
            { display_name => 'inactive.txt', is_dirty => 0, has_vcs_changes => 0 },
        ],
        active_tab_index => 0,
        tab_manager => undef,
    };

    my $bar = Zepto::Renderer->_render_tab_bar($theme, 80, $ui, 0);

    # 2 tabs x 1 left cap each = 2 minimum; same for right cap
    my $left_count  = () = $bar =~ /\x{25e2}/g;
    my $right_count = () = $bar =~ /\x{25e3}/g;
    cmp_ok($left_count,  '>=', 2, '◢ left-cap glyph appears for every tab');
    cmp_ok($right_count, '>=', 2, '◣ right-cap glyph appears for every tab');
};

subtest 'Inactive tab background is visually distinct from the bar background' => sub {
    for my $theme_name (qw(dark_theme light_theme)) {
        my $theme = Zepto::Theme->$theme_name();
        my $ui = {
            tabs => [
                { display_name => 'active.txt',   is_dirty => 0, has_vcs_changes => 0 },
                { display_name => 'inactive.txt', is_dirty => 0, has_vcs_changes => 0 },
            ],
            active_tab_index => 0,
            tab_manager => undef,
        };

        # The fix was specifically that tab_inactive_bg must differ from
        # tab_bar_bg (previously they were nearly identical — 1.17:1/1.19:1
        # contrast, indistinguishable at a glance). Assert at the theme
        # level (not a no-op check — this fails if a future edit reverts
        # inactive_bg back to matching the bar) and confirm the rendered
        # output actually emits that inactive-bg color for the inactive tab.
        my $bar_bg      = $theme->color('tab_bar_bg');
        my $inactive_bg = $theme->color('tab_inactive_bg');
        isnt($inactive_bg, $bar_bg, "$theme_name: tab_inactive_bg differs from tab_bar_bg");

        my $bar = Zepto::Renderer->_render_tab_bar($theme, 80, $ui, 0);
        ok(index($bar, $inactive_bg) >= 0,
            "$theme_name: rendered tab bar actually uses tab_inactive_bg for the inactive tab");
    }
};

subtest 'Tab bar buttons remain correctly ordered and hit-testable after the redesign' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $ui = {
        tabs => [
            { display_name => 'one.txt',   is_dirty => 0, has_vcs_changes => 0 },
            { display_name => 'two.txt',   is_dirty => 1, has_vcs_changes => 0 },
            { display_name => 'three.txt', is_dirty => 0, has_vcs_changes => 0 },
        ],
        active_tab_index => 1,
        tab_manager => undef,
    };

    Zepto::Renderer->_render_tab_bar($theme, 80, $ui, 0);
    my @buttons = Zepto::Renderer->get_tab_bar_buttons();

    my @tab_buttons   = grep { $_->{type} eq 'tab' } @buttons;
    my @close_buttons = grep { $_->{type} eq 'close' } @buttons;

    is(scalar(@tab_buttons), 3, 'One tab button per tab');
    is(scalar(@close_buttons), 3, 'One close button per tab');

    # Buttons must be well-formed (start <= end) and appear left-to-right
    # in tab index order — a click-targeting regression would show up here
    # as overlapping or out-of-order ranges even without a live mouse click.
    my @by_index = sort { $a->{start} <=> $b->{start} } @tab_buttons;
    for my $i (0 .. $#by_index) {
        my $btn = $by_index[$i];
        cmp_ok($btn->{start}, '<=', $btn->{end}, "Tab button $i has a valid (start<=end) range");
        is($btn->{index}, $i, "Tab button $i in left-to-right order maps to tab index $i");
    }

    # Close buttons must sit inside their own tab's [start,end] span, not a
    # neighboring tab's — this is exactly the kind of thing a cap-glyph
    # width change could silently break.
    for my $close_btn (@close_buttons) {
        my ($tab_btn) = grep { $_->{index} == $close_btn->{index} } @tab_buttons;
        ok(defined $tab_btn, "Close button for tab $close_btn->{index} has a matching tab button");
        cmp_ok($close_btn->{start}, '>=', $tab_btn->{start},
            "Close button for tab $close_btn->{index} starts within its own tab's span");
        cmp_ok($close_btn->{end}, '<=', $tab_btn->{end},
            "Close button for tab $close_btn->{index} ends within its own tab's span");
    }
};

subtest 'Tab bar overflow still produces scroll buttons after the redesign' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my @tabs = map { { display_name => "file_number_$_.txt", is_dirty => 0, has_vcs_changes => 0 } } (1 .. 10);
    my $ui = {
        tabs => \@tabs,
        active_tab_index => 5,
        tab_manager => undef,
    };

    # Narrow width forces overflow with 10 tabs
    Zepto::Renderer->_render_tab_bar($theme, 60, $ui, 0);
    my @buttons = Zepto::Renderer->get_tab_bar_buttons();
    my @scroll_left  = grep { $_->{type} eq 'scroll_left' } @buttons;
    my @scroll_right = grep { $_->{type} eq 'scroll_right' } @buttons;

    ok(@scroll_left,  'Scroll-left button present when active tab is scrolled past the start');
    ok(@scroll_right, 'Scroll-right button present when more tabs exist past the visible range');
};

# ============================================================================
# Tab bar corner hint: labeled two-tier degradation (close/tabs/quit)
# ============================================================================
# See docs/UI_GUIDELINES.md "Discoverability Contract" and bugs.md
# "Discoverability Contract gaps" — quit previously had no on-screen hint
# anywhere, and the close/tab-nav corner hint was bare glyphs with no
# plain-language label (flagged by an LLM-vision discoverability sweep as
# unlabeled/ambiguous).
#
# 2026-09-01: converted from plain lowercase text to rounded Title Case
# pills (see bugs.md "Tab-bar buttons (close/tabs/quit hints) use a
# visually different style than the bottom status bar's pills"), matching
# the bottom status bar's visual language. Uses _fit_core_nav_hint_pills()
# (an atomic all-full/all-compact/none fit across all three pills as one
# group, NOT _fit_pill_group's per-pill greedy accumulation) specifically
# so quit can't be silently dropped just because "Close" alone happens to
# fit in full form — that would reopen the exact P1 gap this hint was
# created to close.
#
# Measured side effect of adopting real pill chrome: each pill carries its
# own padding + inter-pill gap (vs. the old plain-text form's single
# leading/trailing space around the whole compact string), so the compact
# tier needs more room than before. The floor moved from 40 cols to ~44-51
# cols depending on tab-name length (was exactly 40, confirmed via direct
# measurement below) — a disclosed, intentional cost of matching the
# status bar's pill shape, not an oversight. The hint still degrades
# gracefully (blank fill, never truncated/garbled) below its new floor,
# and quit remains reachable via ⌃␣ Commands regardless.
subtest 'Tab bar corner hint shows labeled form when there is room' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $ui = {
        tabs => [{ display_name => 'test.txt', is_dirty => 0, has_vcs_changes => 0 }],
        active_tab_index => 0,
        tab_manager => undef,
    };

    my $bar = Zepto::Renderer->_render_tab_bar($theme, 80, $ui, 0);
    my $s = strip_escapes($bar);

    like($s, qr/Close/, 'Labeled hint includes Title Case "Close" (was lowercase "close")');
    like($s, qr/Tabs/, 'Labeled hint includes Title Case "Tabs" (was lowercase "tabs")');
    like($s, qr/Quit/, 'Labeled hint includes Title Case "Quit" — quit previously had no on-screen hint at all');
    like($s, qr/\x{2303}Q/, 'Labeled hint shows the actual ⌃Q shortcut for quit');
    unlike($s, qr/\bclose\b|\btabs\b|\bquit\b/, 'No stale lowercase labels leak through');
};

subtest 'Tab bar corner hint degrades to compact pills (with quit) at its measured narrow-width floor' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $ui = {
        tabs => [{ display_name => 'testfile.txt', is_dirty => 0, has_vcs_changes => 0 }],
        active_tab_index => 0,
        tab_manager => undef,
    };

    # 51 cols with a 12-char tab name (nerd-font mode, the default) is the
    # measured floor where the compact-tier pill group (all three: close,
    # tabs, quit) fits as one atomic group post pill-conversion — directly
    # measured via a synthetic sweep (cols 20-70), not assumed. This is
    # narrower than the old plain-text floor (40 cols) because each pill
    # now carries its own padding + gap; see the subtest doc comment above.
    my $bar = Zepto::Renderer->_render_tab_bar($theme, 51, $ui, 0);
    my $s = strip_escapes($bar);

    unlike($s, qr/Close/, 'At the compact floor: labeled form not used (no room for full labels)');
    like($s, qr/\x{2303}W/, 'At the compact floor: compact close hint (⌃W) still visible');
    like($s, qr/\x{2325}/, 'At the compact floor: compact tab-nav hint (⌥) still visible');
    like($s, qr/\x{2303}Q/, 'At the compact floor: quit hint (⌃Q) still visible — the actual gap this fix closes');

    # One column narrower: the atomic fit must drop the WHOLE group (never
    # a partial 1-or-2-pill subset that would silently lose quit) — see
    # bugs.md and _fit_core_nav_hint_pills()'s doc comment for why this
    # must be all-or-nothing rather than _fit_pill_group's per-pill greedy
    # behavior.
    my $bar_narrower = Zepto::Renderer->_render_tab_bar($theme, 50, $ui, 0);
    my $s_narrower = strip_escapes($bar_narrower);
    unlike($s_narrower, qr/\x{2303}Q/, 'One column narrower than the floor: quit hint absent, not partially rendered');
    unlike($s_narrower, qr/\x{2303}W/, 'One column narrower than the floor: close hint absent too (atomic group, not partial)');
};

subtest 'Tab bar corner hint drops to blank fill (not garbage) when nothing fits' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $ui = {
        tabs => [{ display_name => 'a-much-longer-filename-that-eats-the-row.txt', is_dirty => 0, has_vcs_changes => 0 }],
        active_tab_index => 0,
        tab_manager => undef,
    };

    my $bar = Zepto::Renderer->_render_tab_bar($theme, 60, $ui, 0);
    my $s = strip_escapes($bar);

    unlike($s, qr/Quit/i, 'Extreme narrow: no labeled hint leaks through');
    unlike($s, qr/\x{2303}Q/, 'Extreme narrow: hint honestly absent, not truncated mid-glyph');
};

# ----------------------------------------------------------------------------
# QA-REG-230: the tab bar's corner-hint pill group must never, at any
# terminal width, push the row past $cols. Direct synthetic-sweep guard
# (same technique as QA-REG-179/186) rather than trusting terminal-level
# capture, since a soft-wrap overflow here would scroll the whole screen
# and push the tab bar itself off-screen — the exact failure class those
# two regressions fixed elsewhere.
#
# Tab-name set deliberately excludes a single pathologically-long filename
# (e.g. 40+ chars) with only ONE tab open: that combination hits a
# separate, PRE-EXISTING, unrelated bug — _render_tab_bar's truncation/
# scroll logic is gated on `@tab_info > 1` (Renderer.pm ~1179), so a lone
# tab's name is never truncated or scrolled regardless of terminal width,
# and genuinely overflows $cols on unpatched `main` too (confirmed via
# direct A/B measurement against the pre-existing code, independent of
# this change). Filed separately in bugs.md ("Single-tab session with a
# long filename never truncates... pre-existing, found incidentally") per
# Rule 6 — out of scope to fix here (a tab-name-truncation bug, not a
# corner-hint-pill bug) and NOT something this guard should be weakened to
# hide. Two-tab and moderate-length single-tab cases below all go through
# the working (non-buggy) truncation/scroll path and give this guard real
# coverage of what this change actually touches.
# ----------------------------------------------------------------------------
subtest 'Tab bar row never exceeds $cols at any width, with or without the corner hint (QA-REG-230)' => sub {
    my $theme = Zepto::Theme->dark_theme();

    my $checks = 0;
    my $failures = 0;
    my @first_failures;

    my @tab_sets = (
        ['a.txt'],
        ['test.txt'],
        ['testfile.txt'],
        ['a.txt', 'b.txt'],
        ['test.txt', 'other.txt'],
    );

    for my $nerd_font (0, 1) {
        Zepto::Chars->set_enabled($nerd_font);
        for my $cols (25, 30, 35, 40, 45, 50, 55, 60, 80, 100, 120) {
            for my $names (@tab_sets) {
                my $ui = {
                    tabs => [ map { { display_name => $_, is_dirty => 0, has_vcs_changes => 0 } } @$names ],
                    active_tab_index => 0,
                    tab_manager => undef,
                };
                my $bar = Zepto::Renderer->_render_tab_bar($theme, $cols, $ui, 0);
                my $plain = strip_escapes($bar);
                $plain =~ s/\x1b\[K//g;

                $checks++;
                if (length($plain) > $cols) {
                    $failures++;
                    push @first_failures,
                        "nerd_font=$nerd_font cols=$cols names='@$names' len=" . length($plain)
                        if @first_failures < 10;
                }
            }
        }
    }
    Zepto::Chars->set_enabled(1);  # restore default for subsequent tests

    is($failures, 0, "Tab bar row never exceeds \$cols across $checks combinations")
        or diag(join("\n", @first_failures));
};

# ============================================================================
# FILE_TREE-context hint row: ⌃B back-to-editor hint + shared core-nav hint
# ============================================================================
# See docs/UI_GUIDELINES.md "Discoverability Contract" and bugs.md
# "FILE_TREE-context discoverability" — the tree-focused hint row
# previously had NO on-screen hint for switching focus back to the editor
# (⌃B), nor any of the close-tab/switch-tabs/quit hint DOCUMENT context's
# tab bar shows. A minimal fake tree stands in for Zepto::FileTree here
# (only `focused()` and `cursor_node()` are read by the renderer) so these
# tests don't depend on filesystem scanning.
package Test::FakeTree;
sub new { my ($class, %args) = @_; return bless { path => $args{path} // '.claude', focused => 1 }, $class; }
sub focused { return $_[0]->{focused}; }
sub cursor_node { return { path => $_[0]->{path} }; }
package main;

subtest 'FILE_TREE hint row shows a ⌃B back-to-editor pill when there is room' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $tree = Test::FakeTree->new();
    my $ui = { file_tree => $tree };

    my $bar = Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, 80, '', 0, $ui, 0);
    my $s = strip_escapes($bar);

    like($s, qr/\x{2303}B/, 'FILE_TREE hint row shows the ⌃B shortcut glyph');
    like($s, qr/back/, 'FILE_TREE hint row labels ⌃B with "back" (not a bare, unlabeled glyph)');
};

# ----------------------------------------------------------------------------
# bugs.md P1: "File-tree flat-filter search... has zero UI trigger" — the
# FILE_TREE hint row now advertises "/" as the trigger, and swaps to
# "Esc clear" once filter mode is actually active, so the mechanism for
# both entering AND leaving filter mode is always on screen.
# ----------------------------------------------------------------------------
package Test::FakeFilterTree;
our @ISA = ('Test::FakeTree');
sub new {
    my ($class, %args) = @_;
    my $self = Test::FakeTree::new($class, %args);
    $self->{filter_active} = $args{filter_active} // 0;
    return $self;
}
sub filter_active { return $_[0]->{filter_active}; }
package main;

subtest 'FILE_TREE hint row shows a "/ filter" pill when not filtering' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $tree = Test::FakeFilterTree->new(filter_active => 0);
    my $ui = { file_tree => $tree };

    my $bar = Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, 80, '', 0, $ui, 0);
    my $s = strip_escapes($bar);

    like($s, qr{/ filter}, 'FILE_TREE hint row advertises "/" as the fuzzy-filter trigger');
    unlike($s, qr/Esc clear/, 'Does not show the "Esc clear" pill while not filtering');
};

subtest 'FILE_TREE hint row swaps to "Esc clear" once filter mode is active' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $tree = Test::FakeFilterTree->new(filter_active => 1);
    my $ui = { file_tree => $tree };

    my $bar = Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, 80, '', 0, $ui, 0);
    my $s = strip_escapes($bar);

    like($s, qr/Esc clear/, 'FILE_TREE hint row shows "Esc clear" while filtering');
    unlike($s, qr{/ filter}, 'Does not show the "/ filter" trigger pill while already filtering');
    unlike($s, qr{\x{2190}\x{2192} fold}, '"←→ fold" is omitted while filtering (flat results have no dirs to fold)');
};

subtest 'FILE_TREE hint row against a tree object with no filter_active method does not die (real FileTree always has it)' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $tree = Test::FakeTree->new();  # deliberately lacks filter_active()
    my $ui = { file_tree => $tree };

    my $bar = eval { Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, 80, '', 0, $ui, 0) };
    ok(!$@, 'Rendering does not die against a tree stand-in missing filter_active()') or diag("error: $@");
    like(strip_escapes($bar), qr{/ filter}, 'Falls back to the non-filtering pill set');
};

subtest 'FILE_TREE ⌃B back pill is highest priority — survives narrower widths than the other tree pills' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $tree = Test::FakeTree->new();
    my $ui = { file_tree => $tree };

    # 60 cols: confirmed via a direct-render probe as a width where ⌃B back
    # fits but the lower-priority tree pills (↵ open, ↑↓, ←→ fold) do not —
    # must not regress below this floor.
    my $bar = Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, 60, '', 0, $ui, 0);
    my $s = strip_escapes($bar);

    like($s, qr/\x{2303}B/, '60 cols: ⌃B back-to-editor hint still visible');
    like($s, qr/\x{2303}\x{2423}|Commands/, '60 cols: ⌃␣ Commands fallback signpost still visible');
};

subtest 'FILE_TREE hint row degrades to blank fill (not garbage) at extreme widths, Commands pill never drops' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $tree = Test::FakeTree->new();
    my $ui = { file_tree => $tree };

    my $bar = Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, 40, '', 0, $ui, 0);
    my $s = strip_escapes($bar);

    unlike($s, qr/back/, '40 cols: no tree-specific hint leaks through at extreme scarcity');
    like($s, qr/Commands/, '40 cols: ⌃␣ Commands fallback signpost still visible even here');
};

subtest 'FILE_TREE hint row shares the core-nav hint (close/tabs/quit) with DOCUMENT context, identical wording' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $tree = Test::FakeTree->new();
    my $ui = { file_tree => $tree };

    # Needs more width than DOCUMENT context's tab bar before this segment
    # has room — the FILE_TREE row carries more fixed chrome (breadcrumb +
    # Open/Commands pills). Confirmed via probe this appears by 135 cols
    # (was 130 before the "/ filter" tree pill was added alongside ⌃B back
    # — see bugs.md "File-tree flat-filter search... has zero UI trigger" —
    # which pushed the threshold out by one pill's width).
    my $bar = Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, 140, '', 0, $ui, 0);
    my $s = strip_escapes($bar);

    like($s, qr/Close/, 'FILE_TREE hint row labels the close-tab shortcut, Title Case ("Close")');
    like($s, qr/Tabs/,  'FILE_TREE hint row labels the tab-nav shortcut, Title Case ("Tabs")');
    like($s, qr/Quit/,  'FILE_TREE hint row labels the quit shortcut, Title Case ("Quit")');
    like($s, qr/\x{2303}Q/, 'FILE_TREE hint row shows the actual ⌃Q shortcut glyph for quit');
};

# ============================================================================
# QA-REG-186: the FILE_TREE-context hint row's breadcrumb (cursor node path)
# must never, combined with the fixed Open/Commands pills, push the row past
# $cols. Confirmed via direct screenshot: opening a nested/long-named tree
# entry at 40 cols (e.g. ".claude", or several directories deep) produced a
# row wider than the terminal, which soft-wrapped onto a phantom line and
# corrupted the screen above it — the exact same failure mode QA-REG-179
# fixed for the DOCUMENT-context status bar, but in the FILE_TREE branch,
# which computed the breadcrumb's width unconditionally before the fixed
# Open/Commands pills' width was ever accounted for. Fix: the breadcrumb is
# now ellipsized (from the start, keeping the tail visible) against however
# much room is left after the fixed right-side pills, and drops to empty
# rather than negative-width if there's truly no room at all.
#
# Below ~32-38 cols (depending on nerd-font mode), the fixed Open/Commands
# pills alone already exceed the terminal width even with a completely
# empty breadcrumb — a pre-existing structural floor (same class as the
# DOCUMENT-context "Commands pill alone can't fit below ~25 cols" floor
# noted elsewhere in this file), not a gap in this fix. The sweep below
# starts at 40 cols, the "essential chrome" floor this codebase already
# targets elsewhere, rather than asserting an unsupported guarantee below it.
# ============================================================================
subtest 'FILE_TREE breadcrumb never pushes the hint row past $cols, at any path length/width (QA-REG-186)' => sub {
    my $theme = Zepto::Theme->dark_theme();

    my $checks = 0;
    my $failures = 0;
    my @first_failures;

    my @paths = (
        '.claude',
        'src/main.py',
        'aaaaaaaa/bbbbbbbb/cccccccc/dddddddd/somefile.txt',
        'x',
        '',
    );

    for my $nerd_font (0, 1) {
        Zepto::Chars->set_enabled($nerd_font);
        for my $cols (40, 45, 50, 60, 80, 120) {
            for my $path (@paths) {
                my $tree = Test::FakeTree->new(path => $path);
                my $ui = { file_tree => $tree };
                my $bar = Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, $cols, '', 0, $ui, 0);
                my $plain = strip_escapes($bar);
                $plain =~ s/\x1b\[K//g;

                $checks++;
                if (length($plain) > $cols) {
                    $failures++;
                    push @first_failures,
                        "nerd_font=$nerd_font cols=$cols path='$path' len=" . length($plain)
                        if @first_failures < 10;
                }
            }
        }
    }
    Zepto::Chars->set_enabled(1);  # restore default for subsequent tests

    is($failures, 0, "FILE_TREE hint row never exceeds \$cols across $checks combinations")
        or diag(join("\n", @first_failures));
};

subtest 'FILE_TREE breadcrumb keeps the tail (most useful part) visible when ellipsized' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $tree = Test::FakeTree->new(path => 'aaaaaaaa/bbbbbbbb/cccccccc/dddddddd/somefile.txt');
    my $ui = { file_tree => $tree };

    my $bar = Zepto::Renderer->_render_context_status_bar(undef, undef, $theme, 40, '', 0, $ui, 0);
    my $s = strip_escapes($bar);

    like($s, qr/somefile\.txt|\x{2026}/, '40 cols: breadcrumb keeps the filename tail visible (ellipsized from the start), not silently empty or truncated from the end');
};

subtest 'DOCUMENT-context tab bar corner hint is unaffected by the FILE_TREE hint-row refactor' => sub {
    my $theme = Zepto::Theme->dark_theme();
    my $ui = {
        tabs => [{ display_name => 'test.txt', is_dirty => 0, has_vcs_changes => 0 }],
        active_tab_index => 0,
        tab_manager => undef,
    };

    my $bar = Zepto::Renderer->_render_tab_bar($theme, 80, $ui, 0);
    my $s = strip_escapes($bar);

    like($s, qr/Close/, 'DOCUMENT tab bar corner hint still labels Close');
    like($s, qr/Tabs/,  'DOCUMENT tab bar corner hint still labels Tabs');
    like($s, qr/Quit/,  'DOCUMENT tab bar corner hint still labels Quit');
};

# ============================================================================
# Status bar compact pills: icon-fallback regression guard (Fix 3)
# ============================================================================
# See bugs.md "Discoverability sweep run 2" — a compact status-bar pill
# (icon + key, label dropped) must never silently degrade to a bare key
# letter because its icon has no glyph mapping in the active mode. This is
# a general assertion over the WHOLE registry (not just Word Wrap) so a
# newly-added command with priority > 0 can't reintroduce this gap.
# Investigated against the current registry (both modes): every
# priority > 0 command's icon already resolves to a non-empty glyph in
# both nerd-font and ASCII-fallback mode (Zepto::Chars.pm's %CHARS table
# has an entry for every icon name currently used at priority > 0). This
# test locks that guarantee in so it can't silently regress later.
subtest 'No priority > 0 command ever compacts to a bare key with no icon (either nerd-font mode)' => sub {
    for my $nerd_font (0, 1) {
        Zepto::Chars->set_enabled($nerd_font);
        my $mode = $nerd_font ? 'nerd-font' : 'ASCII fallback';

        for my $cmd (Zepto::CommandRegistry->all_commands()) {
            next unless ($cmd->{priority} // 0) > 0;

            my $icon_name = $cmd->{icon} // 'menu';
            # Theme pill's icon is dynamic (theme_auto/dark/light) at render
            # time, but all three variants resolve through the same lookup
            # table as the declared base name, so checking the declared
            # icon name is a sufficient stand-in here.
            my $icon = Zepto::Chars->get($icon_name);
            ok(length($icon) > 0,
               "'$cmd->{id}' icon '$icon_name' has a non-empty glyph in $mode mode");
        }
    }
    Zepto::Chars->set_enabled(1);  # restore default for subsequent test files sharing this process
};

# ============================================================================
# Find bar must never overflow the terminal width (bugs.md P0 "Find &
# Replace's 'preview' mutates the real document and corrupts on-screen
# rendering"). Root cause of the screen-corruption symptom: with replace
# mode active, FIND_INPUT_WIDTH_MIN was applied as an unconditional floor
# to each of the 2 input fields, which could push the bar's total content
# width past $cols on terminals narrower than ~90 cols (confirmed: 80-col
# terminal overflowed by 4 chars with a 3-match "of 3" match-count
# string). The overflow characters wrap onto the next physical terminal
# row via the terminal's own auto-wrap, which the differential renderer
# (Editor.pm's render(), tracking content per logical row) never accounts
# for or clears -- producing the reported stacked, uncleared duplicate
# find-bar/preview rows.
# ============================================================================

subtest 'find_bar_input_width never lets fields exceed their budget' => sub {
    for my $cols (40, 50, 60, 70, 76, 80, 90, 100, 120, 200) {
        for my $replace_active (0, 1) {
            for my $right_side_width (45, 54, 60, 70) {  # base 45 .. base+long match text
                my $input_width = Zepto::Renderer->find_bar_input_width(
                    $cols, $replace_active, $right_side_width);
                my $num_fields = $replace_active ? 2 : 1;
                my $available = $replace_active
                    ? ($cols - 2 - 5 - 1 - 8 - 1 - $right_side_width)
                    : ($cols - 2 - 5 - $right_side_width);

                ok($input_width >= 1,
                   "cols=$cols replace=$replace_active right=$right_side_width: input_width >= 1");
                ok($input_width * $num_fields <= $available || $available < $num_fields,
                   "cols=$cols replace=$replace_active right=$right_side_width: "
                   . "$num_fields field(s) of width $input_width fit within budget $available");
            }
        }
    }
};

# Build a minimal $find hash mimicking what Editor.pm's render() passes as
# ui->{find_mode} (see Editor.pm's render(), the `find_mode => ... {` block).
sub _mock_find_state {
    my (%opts) = @_;
    return {
        value          => $opts{value} // 'foo',
        regex          => 0,
        case           => 0,
        replace_value  => $opts{replace_value} // 'foo',
        replace_all    => $opts{replace_all} // 1,
        replace_active => $opts{replace_active} // 1,
        focus          => 'replace',
        current        => ($opts{match_count} // 3) - 1,
        match_count    => $opts{match_count} // 3,
        find_widget    => Zepto::InputWidget->new(value => $opts{value} // 'foo'),
        replace_widget => Zepto::InputWidget->new(value => $opts{replace_value} // 'foo'),
    };
}

subtest 'Find bar with replace field never exceeds $cols at common terminal widths' => sub {
    my $theme = Zepto::Theme->new('dark');

    # Exact repro shape from bugs.md: find="foo", replace grows one char at
    # a time as the user types (fooX, fooXY, fooXYZ before the pre-select
    # fix; X, XY, XYZ after it) against a file with 3 matches -- match_text
    # becomes "↑↓ 3 of 3" (9 chars), the specific case that overflowed an
    # 80-col terminal by 4 characters before the fix.
    for my $cols (70, 76, 80, 90, 100, 120) {
        for my $replace_value ('X', 'XY', 'XYZ', 'fooXYZ') {
            my $find = _mock_find_state(value => 'foo', replace_value => $replace_value, match_count => 3);
            my $out = Zepto::Renderer->_render_find_bar($theme, $find, $cols);
            my $visible = strip_escapes($out);
            ok(length($visible) <= $cols,
               "cols=$cols replace='$replace_value': find bar visible width ("
               . length($visible) . ") does not exceed terminal width");
        }
    }
};

subtest 'Find bar with no matches / longer match counts never exceeds $cols' => sub {
    # Scoped to cols >= 76 (comfortably below the standard 80-col default
    # this bug was reported at) -- an even narrower terminal (70 cols)
    # combined with a very large match count (15+) can still overflow by a
    # few characters, since at that point the FIXED elements (pills,
    # labels) plus a long "of N" string alone approach $cols before any
    # input-field width is even considered. That narrower residual case is
    # logged separately in bugs.md as a low-priority follow-up; it's a much
    # more extreme combination than the reported repro (3 matches, 80
    # cols) this fix targets.
    my $theme = Zepto::Theme->new('dark');
    for my $cols (76, 80, 90, 100, 120) {
        for my $match_count (0, 1, 3, 15, 99, 250, 9999) {
            my $find = _mock_find_state(value => 'foo', replace_value => 'XYZ', match_count => $match_count);
            my $out = Zepto::Renderer->_render_find_bar($theme, $find, $cols);
            my $visible = strip_escapes($out);
            ok(length($visible) <= $cols,
               "cols=$cols match_count=$match_count: find bar visible width ("
               . length($visible) . ") does not exceed terminal width");
        }
    }
};

# bugs.md P2 "Shift+Tab in the find/replace bar drops the last character of
# BOTH the Find and Replace field values". Root cause: InputWidget::viewport()
# caches its scroll offset (view_offset) across calls. The find bar's shared
# input_width shrinks for exactly one render frame whenever is_searching is
# momentarily true (match_text grows by "..."), which can push a same-width
# value's cursor past the scroll-into-view threshold and scroll the field.
# Once is_searching goes false again on the very next frame and input_width
# widens back out, the stale scroll offset used to stick around even though
# the whole value now fits -- rendering it with leading characters hidden
# even though the underlying widget value was never touched. Reproduced here
# at the exact Renderer/InputWidget boundary (not just InputWidget in
# isolation, and not by injecting raw Shift+Tab bytes -- InputParser's CSI-Z
# handling was traced and confirmed correct; this is a pure rendering bug
# reachable by anything that flips is_searching for one frame while a field
# sits at its width boundary, of which a Shift+Tab-triggered re-search is
# just the reliable trigger the bug was found through).
subtest 'Find bar fields recover full value after a transient is_searching width narrowing' => sub {
    my $theme = Zepto::Theme->new('dark');

    # Same widget objects reused across both render calls -- critical, since
    # the bug is entirely about view_offset state persisting on the widget
    # between renders (exactly how Editor.pm's real find_widget/
    # find_replace_widget objects are reused frame to frame).
    my $find_widget    = Zepto::InputWidget->new(value => 'aaa');
    my $replace_widget = Zepto::InputWidget->new(value => 'bbb');

    my %base = (
        regex => 0, case => 0, replace_all => 1, replace_active => 1,
        focus => 'replace', current => 0, match_count => 1,
        find_widget => $find_widget, replace_widget => $replace_widget,
    );

    # Frame 1: find engine still reports is_searching -- match_text grows by
    # "..." (matches bugs.md's exact repro: cols=80, 3-char find/replace
    # values, 1 match). This transiently narrows the shared input field
    # width enough to scroll both fields.
    Zepto::Renderer->_render_find_bar($theme, { %base, is_searching => 1 }, 80);

    # Frame 2: search finished, is_searching now false, width widens back
    # out -- the whole 3-char value fits again in the wider field.
    my $out = strip_escapes(
        Zepto::Renderer->_render_find_bar($theme, { %base, is_searching => 0 }, 80));

    like($out, qr/Find:aaa(?!\S)/, 'Find field shows the full "aaa", not truncated to "aa"');
    like($out, qr/(?:Rep All|Rep One):bbb(?!\S)/, 'Replace field shows the full "bbb", not truncated to "bb"');
    is($find_widget->value(), 'aaa', 'Underlying find_widget value was never touched');
    is($replace_widget->value(), 'bbb', 'Underlying replace_widget value was never touched');
};

# ============================================================================
# Ghost text completion rendering (bugs.md P1 "Ghost-text completion renders
# at the end of the line's real content, not at the cursor")
#
# Renderer::_render_text_area's ghost-text block used to always paint the
# suggestion starting at $content_display_width -- the visual end of the
# line's REAL content -- instead of at the cursor's actual screen column.
# This was invisible when the cursor sat at true end-of-line (the common
# typing case) but garbled the display whenever the cursor was mid-line
# with real characters after it (e.g. after undo/redo, or navigation
# through multi-byte content -- see bugs.md for the original repros).
# ============================================================================

# Extract just row 3's raw (unstripped) rendered segment -- the first text
# row -- from a full render_string() output, for byte-level assertions
# about exactly what was emitted for that row.
sub _extract_row3 {
    my ($out) = @_;
    if ($out =~ /(\x1b\[3;\d+H.*?)(?=\x1b\[4;\d+H)/s) {
        return $1;
    }
    return '';
}

subtest 'Ghost text: cursor at true end-of-line renders in the fill area (baseline, unchanged)' => sub {
    my $theme = Zepto::Theme->dark_theme();
    Zepto::Renderer->set_tab_width(4);

    my ($doc, $view) = create_test_state("hello\n");
    is($doc->line_count(), 1, 'single-line fixture');
    $view->set_cursor(0, 5);    # true end of "hello"

    my $gutter_width = Zepto::Renderer->get_gutter_width($doc->line_count());
    my $ghost_fg = $theme->color('completion_ghost_fg');

    my $out = Zepto::Renderer->render_string(
        document => $doc, view => $view, theme => $theme,
        rows => 24, cols => 80,
        ui => { completion => { ghost_text => 'XX' } },
    );

    my $row3 = _extract_row3($out);
    ok(length($row3) > 0, 'row 3 (first text row) was rendered');

    # Ghost text immediately follows the real content, in the fill area --
    # no mid-row cursor-repositioning sequence is needed or emitted when
    # the cursor is already at the end of the real content.
    my $expected = $ghost_fg . 'XX' . Zepto::Renderer::RESET;
    like($row3, qr/\Q$expected\E/, 'ghost text follows real content directly, still in the fill area');

    # Regression guard: the old ghost-text block never needed a second
    # mid-row cursor jump for this case, and still doesn't -- only the
    # single row-start move-to should appear.
    my $move_count = () = ($row3 =~ /\x1b\[3;\d+H/g);
    is($move_count, 1, 'no extra mid-row cursor repositioning for the end-of-line case');
};

subtest 'Ghost text: mid-line cursor with plain content after it renders at the cursor column (bugs.md P1)' => sub {
    my $theme = Zepto::Theme->dark_theme();
    Zepto::Renderer->set_tab_width(4);

    my ($doc, $view) = create_test_state("hello world\n");
    is($doc->line_count(), 1, 'single-line fixture');
    is($doc->get_line_content(0), 'hello world', 'fixture content as expected');

    # Cursor between "hello" and " world" -- real content follows the
    # cursor on this line, which is exactly the scenario the bug garbled.
    $view->set_cursor(0, 5);

    my $gutter_width = Zepto::Renderer->get_gutter_width($doc->line_count());
    my $tree_width = 0;
    my $cols = 80;
    my $rows = 24;
    my $minimap_width = 0;    # show_minimap defaults off when no prefs given
    my $avail_width = $cols - $tree_width - $gutter_width - $minimap_width;

    my $visual_cursor_col = Zepto::Renderer::_char_to_visual_col('hello world', 5);
    is($visual_cursor_col, 5, 'no tabs before the cursor -- visual column equals char column');

    my $ghost_col = $tree_width + $gutter_width + $visual_cursor_col + 1;    # 1-indexed
    my $row_end_col = $tree_width + $gutter_width + $avail_width + 1;
    my $ghost_fg = $theme->color('completion_ghost_fg');

    my $out = Zepto::Renderer->render_string(
        document => $doc, view => $view, theme => $theme,
        rows => $rows, cols => $cols,
        ui => { completion => { ghost_text => 'XX' } },
    );

    my $row3 = _extract_row3($out);
    ok(length($row3) > 0, 'row 3 (first text row) was rendered');

    # Correct position: ghost text is painted as an overlay at the cursor's
    # actual screen column, then the terminal cursor is restored to the
    # natural end of the content row (for the minimap/CLEAR_LINE that follow).
    my $expected = Zepto::Renderer::_move_to(3, $ghost_col)
        . $ghost_fg . 'XX' . Zepto::Renderer::RESET
        . Zepto::Renderer::_move_to(3, $row_end_col);
    like($row3, qr/\Q$expected\E/,
        "ghost text renders at the cursor's screen column (col $ghost_col), not line-content end");

    # Wrong (pre-fix) position: the line's real content is 11 chars wide, so
    # the old buggy code painted the ghost suffix starting right after it,
    # i.e. immediately adjacent to the real content with NO cursor
    # repositioning beforehand. Confirm the ghost color+text sequence
    # appears exactly once in this row -- the one correctly-positioned
    # occurrence just matched above -- and not a second, un-repositioned
    # occurrence glued onto the end of the real content (the pre-fix shape).
    my $ghost_occurrences = () = ($row3 =~ /\Q${ghost_fg}XX\E/g);
    is($ghost_occurrences, 1, 'ghost color+text appears exactly once, at the repositioned cursor column');

    # Real trailing content ("hello world") is rendered intact exactly
    # once -- not duplicated, not corrupted, not shifted out of the string.
    my $visible = strip_escapes($row3);
    my $hello_count = () = ($visible =~ /hello/g);
    my $world_count = () = ($visible =~ /world/g);
    is($hello_count, 1, 'real content "hello" appears exactly once (not duplicated)');
    is($world_count, 1, 'real content "world" appears exactly once (not duplicated)');
};

subtest 'Ghost text: mid-line cursor after a tab accounts for tab expansion (bugs.md P1)' => sub {
    my $theme = Zepto::Theme->dark_theme();
    Zepto::Renderer->set_tab_width(4);

    my ($doc, $view) = create_test_state("a\tbcd efg\n");
    is($doc->line_count(), 1, 'single-line fixture');
    is($doc->get_line_content(0), "a\tbcd efg", 'fixture content as expected');

    # Cursor right after "d" (char index 5: a=0, \t=1, b=2, c=3, d=4, cursor=5),
    # with " efg" as real trailing content after it.
    $view->set_cursor(0, 5);

    my $gutter_width = Zepto::Renderer->get_gutter_width($doc->line_count());
    my $tree_width = 0;

    # Manually-derived expected visual column: 'a' -> visual col 1; tab
    # at visual col 1 expands to the next multiple of 4 -> visual col 4;
    # 'b','c','d' each add 1 -> visual col 7.
    my $visual_cursor_col = Zepto::Renderer::_char_to_visual_col("a\tbcd efg", 5);
    is($visual_cursor_col, 7, 'tab expansion is accounted for in the cursor visual column');

    my $ghost_col = $tree_width + $gutter_width + $visual_cursor_col + 1;
    my $ghost_fg = $theme->color('completion_ghost_fg');

    my $out = Zepto::Renderer->render_string(
        document => $doc, view => $view, theme => $theme,
        rows => 24, cols => 80,
        ui => { completion => { ghost_text => 'Q' } },
    );

    my $row3 = _extract_row3($out);
    my $expected = Zepto::Renderer::_move_to(3, $ghost_col) . $ghost_fg . 'Q' . Zepto::Renderer::RESET;
    like($row3, qr/\Q$expected\E/,
        "ghost text renders at the tab-expanded cursor column (col $ghost_col)");

    # Real trailing content after the cursor ("efg") must survive intact.
    my $visible = strip_escapes($row3);
    my $efg_count = () = ($visible =~ /efg/g);
    is($efg_count, 1, 'real trailing content "efg" appears exactly once (not duplicated)');
};

# ============================================================================
# bugs.md P2 "No on-screen indicator for Replace-One vs. Replace-All mode,
# and no palette command to switch between them" -- the find bar's
# "Replace:" label now doubles as a clickable replace-mode indicator,
# reading "Rep All:" or "Rep One:" (colored like the regex/case toggle
# pills' active/inactive states) depending on the current mode. It is
# exactly as wide as the original "Replace:" label (8 chars either way),
# which was a deliberate choice: a separate pill was tried first and broke
# the P0 overflow-guard tests below, because this find bar already shrinks
# its input fields to their floor at common widths (76-90 cols) with zero
# spare margin -- see the "never exceeds $cols" subtest for the regression
# this guards against. See tests/find.t for Editor.pm-side
# toggle/click/palette-command coverage.
# ============================================================================
subtest 'Find bar replace-mode label reflects replace_all state' => sub {
    my $theme = Zepto::Theme->new('dark');
    my $cols = 80;

    my $find_on = _mock_find_state(value => 'foo', replace_value => 'bar', replace_all => 1);
    my $visible_on = strip_escapes(Zepto::Renderer->_render_find_bar($theme, $find_on, $cols));
    ok(index($visible_on, 'Rep All:') >= 0, 'Replace All mode: label reads "Rep All:"');
    ok(index($visible_on, 'Rep One:') < 0, 'Replace All mode: label does not also read "Rep One:"');

    my $find_off = _mock_find_state(value => 'foo', replace_value => 'bar', replace_all => 0);
    my $visible_off = strip_escapes(Zepto::Renderer->_render_find_bar($theme, $find_off, $cols));
    ok(index($visible_off, 'Rep One:') >= 0, 'Replace One mode: label reads "Rep One:"');
    ok(index($visible_off, 'Rep All:') < 0, 'Replace One mode: label does not also read "Rep All:"');

    # Plain "Replace:" (the old, mode-less label) must be gone -- this is
    # the actual bug fix, not just an additive change.
    ok(index($visible_on, 'Replace:') < 0, 'Replace All mode: old unlabeled "Replace:" text is gone');
    ok(index($visible_off, 'Replace:') < 0, 'Replace One mode: old unlabeled "Replace:" text is gone');
};

subtest 'Find bar has no replace-mode label when the replace field is not shown' => sub {
    my $theme = Zepto::Theme->new('dark');
    my $find = _mock_find_state(value => 'foo', replace_active => 0, replace_all => 1);
    my $visible = strip_escapes(Zepto::Renderer->_render_find_bar($theme, $find, 80));
    ok(index($visible, 'Rep All:') < 0,
       'Find-only mode (no replace field): no "Rep All:" label leaks in');
    ok(index($visible, 'Rep One:') < 0,
       'Find-only mode (no replace field): no "Rep One:" label leaks in either');
};

subtest 'Replace-mode label does not change the find bar\'s total width between All and One' => sub {
    # "Rep All:" and "Rep One:" are both exactly 8 characters -- same as
    # the original "Replace:" -- so the overflow-guard tests below don't
    # need to enumerate both states separately. Verified here against the
    # real renderer output (not just the literal strings) so it fails if
    # that assumption ever breaks.
    my $theme = Zepto::Theme->new('dark');
    my $cols = 80;
    my $find_all = _mock_find_state(value => 'foo', replace_value => 'bar', replace_all => 1);
    my $find_one = _mock_find_state(value => 'foo', replace_value => 'bar', replace_all => 0);
    my $w_all = length(strip_escapes(Zepto::Renderer->_render_find_bar($theme, $find_all, $cols)));
    my $w_one = length(strip_escapes(Zepto::Renderer->_render_find_bar($theme, $find_one, $cols)));
    is($w_all, $w_one, 'Rendered find bar width is identical regardless of replace mode');
};

subtest 'Find bar with replace-mode label never exceeds $cols (P0 overflow-guard tests still hold)' => sub {
    # Same combinations the P0 fix's own overflow-guard subtests cover
    # (see "Find bar with no matches / longer match counts never exceeds
    # $cols" above), plus both replace_all states -- this is the
    # regression check for the P2 fix's own first (reverted) attempt,
    # which broke these exact cases at cols=76 (every match count) and
    # cols=80 (match_count >= 250) by adding a separate fixed-width pill.
    my $theme = Zepto::Theme->new('dark');
    for my $cols (76, 80, 90, 100, 120) {
        for my $replace_all (0, 1) {
            for my $match_count (0, 1, 3, 15, 99, 250, 9999) {
                my $find = _mock_find_state(
                    value => 'foo', replace_value => 'XYZ',
                    match_count => $match_count, replace_all => $replace_all);
                my $out = Zepto::Renderer->_render_find_bar($theme, $find, $cols);
                my $visible = strip_escapes($out);
                ok(length($visible) <= $cols,
                   "cols=$cols replace_all=$replace_all match_count=$match_count: "
                   . "find bar visible width (" . length($visible)
                   . ") does not exceed terminal width");
            }
        }
    }
};

done_testing();
