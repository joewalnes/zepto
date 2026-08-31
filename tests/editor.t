#!/usr/bin/env perl
# Tests for Zepto::Editor
use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempfile tempdir);
use Cwd ();

use Zepto::Editor;
use Zepto::Terminal;
use Zepto::Document;
use Zepto::View;
use Zepto::Preferences;
use Zepto::StateStore;
use Zepto::FindEngine;
use Zepto::Highlighter;

# Create a mock terminal for testing
sub mock_terminal {
    my ($in_fh, $in_name) = tempfile(UNLINK => 1);
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    return Zepto::Terminal->new(in => $in_fh, out => $out_fh);
}

# Helper to create temp file with content
sub create_temp_file {
    my ($content) = @_;
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh $content;
    close $fh;
    return $filename;
}
# Helper to set up document + view in editor's tab manager (replaces direct field assignment)
sub setup_editor_doc {
    my ($editor, $filename) = @_;
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
    return ($doc, $view);
}

# Minimal stand-in for Completion::Controller used by the 'Autocomplete
# toggle' subtest to verify dismiss() is called exactly when the toggle
# turns auto-complete OFF.
package Test::FakeCompletion;
sub new { return bless { dismiss_count => 0 }, shift; }
sub dismiss { my $self = shift; $self->{dismiss_count}++; }
package main;


# ============================================================================
# Construction
# ============================================================================
subtest 'Construction' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    ok($editor, 'Editor created');
};

subtest 'Construction with file' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );
    is($editor->{initial_file}, $filename, 'File path set');
};

subtest 'Construction with preferences' => sub {
    my $term = mock_terminal();
    my $prefs = Zepto::Preferences->new(theme => 'light');
    my $editor = Zepto::Editor->new(
        terminal => $term,
        prefs => $prefs,
    );
    is($editor->{prefs}->theme(), 'light', 'Custom prefs used');
};

# ============================================================================
# State constants
# ============================================================================
subtest 'State constants' => sub {
    is(Zepto::Editor::STATE_EDITING, 'editing', 'STATE_EDITING');
    is(Zepto::Editor::STATE_PALETTE, 'palette', 'STATE_PALETTE');
    is(Zepto::Editor::STATE_DIALOG, 'dialog', 'STATE_DIALOG');
    is(Zepto::Editor::STATE_PROMPT, 'prompt', 'STATE_PROMPT');
    is(Zepto::Editor::STATE_FOOTER_INPUT, 'footer_input', 'STATE_FOOTER_INPUT');
    is(Zepto::Editor::STATE_FIND, 'find', 'STATE_FIND');
    is(Zepto::Editor::STATE_QUIT, 'quit', 'STATE_QUIT');
};

# ============================================================================
# Command palette operations
# ============================================================================
subtest 'Open command palette' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->cmd_open_palette();
    is($editor->{state}, 'palette', 'State is palette');
    is($editor->{palette_widget}->value(), '', 'Query starts empty');
    is($editor->{palette_cursor}, 1, 'Cursor starts at 1 (after section header)');
};

subtest 'Close command palette' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->cmd_open_palette();
    $editor->close_palette();
    is($editor->{state}, 'editing', 'State is editing');
    ok(!defined $editor->{palette_widget}, 'Widget cleared (palette closed)');
};

subtest 'Palette escape closes' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->cmd_open_palette();
    is($editor->{state}, 'palette', 'Palette open');

    $editor->handle_palette_event({ type => 'key', key => 'escape' });
    is($editor->{state}, 'editing', 'Palette closed after escape');
};

# ============================================================================
# Dialog operations
# ============================================================================
subtest 'Open dialog' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->open_dialog(
        title => 'Test',
        prompt => 'Enter:',
        value => 'initial',
    );

    is($editor->{state}, 'dialog', 'State is dialog');
    is($editor->{dialog}{title}, 'Test', 'Dialog title');
    is($editor->{dialog}{prompt}, 'Enter:', 'Dialog prompt');
    is($editor->{dialog}{value}, 'initial', 'Dialog value');
};

subtest 'Close dialog' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->open_dialog(title => 'Test', prompt => 'Input:');
    $editor->close_dialog();

    is($editor->{state}, 'editing', 'State is editing');
    is($editor->{dialog}, undef, 'Dialog cleared');
};

# ============================================================================
# Clipboard operations
# ============================================================================
subtest 'Clipboard' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    is($editor->{clipboard}, '', 'Clipboard initially empty');

    $editor->{clipboard} = 'test content';
    is($editor->{clipboard}, 'test content', 'Clipboard set');
};

# ============================================================================
# Message display
# ============================================================================
subtest 'Show message' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->show_message('Test message');
    is($editor->{message}, 'Test message', 'Message set');
};

# ============================================================================
# message_is_error must not leak onto later non-error messages (QA-REG-142)
# ============================================================================
subtest 'Toggle confirmation does not inherit stale error styling' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    # An error is showing (e.g. from a prior failed action in the same
    # input batch -- run()'s top-of-batch reset only fires once per batch,
    # before any commands in that batch have run).
    $editor->show_error_message('Something went wrong');
    ok($editor->{message_is_error}, 'Error flag set after show_error_message');

    # A toggle command fires next and writes its own confirmation message.
    # That confirmation must render as a normal message, not an error.
    $editor->cmd_toggle_autocomplete();
    is($editor->{message}, 'Auto Complete: OFF', 'Toggle confirmation message set');
    ok(!$editor->{message_is_error}, 'Toggle confirmation is not flagged as an error');
};

# ============================================================================
# Quit handling
# ============================================================================
subtest 'Quit pending' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    is($editor->{quit_pending}, 0, 'Quit not pending initially');
    $editor->{quit_pending} = 1;
    is($editor->{quit_pending}, 1, 'Quit pending set');
};

# ============================================================================
# Theme handling
# ============================================================================
subtest 'Theme change' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{theme}->name(), 'dark', 'Default theme is dark');

    $editor->cmd_toggle_theme();
    is($editor->{theme}->name(), 'light', 'Theme toggled to light');
    is($editor->{prefs}->theme(), 'light', 'Prefs updated');

    $editor->cmd_toggle_theme();
    is($editor->{theme}->name(), 'dark', 'Theme toggled back to dark');
};

# ============================================================================
# Auto theme (P3 "Automatic dark/light mode")
# ============================================================================
# theme_detect_fn / theme_poll_supported_fn are test-only injection points
# on Zepto::Editor->new — production code always leaves them undef and
# calls the real Zepto::ThemeDetect functions. These tests must never
# shell out.
subtest 'Auto theme resolves via injected detector at construction' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
        prefs => Zepto::Preferences->new(theme => 'auto'),
        theme_detect_fn => sub { return 'light'; },
    );

    is($editor->{prefs}->theme(), 'auto', 'Pref stays auto');
    is($editor->{theme}->name(), 'light', 'Effective theme resolved from injected detector');
};

subtest 'Auto theme falls back to dark when detector says dark' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
        prefs => Zepto::Preferences->new(theme => 'auto'),
        theme_detect_fn => sub { return 'dark'; },
    );

    is($editor->{theme}->name(), 'dark', 'Effective theme resolved as dark');
};

subtest 'cmd_set_theme_auto / dark / light jump directly to a mode' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
        theme_detect_fn => sub { return 'light'; },
    );

    is($editor->{prefs}->theme(), 'dark', 'Starts explicit dark');

    $editor->cmd_set_theme_auto();
    is($editor->{prefs}->theme(), 'auto', 'Pref is now auto');
    is($editor->{theme}->name(), 'light', 'Resolved immediately via injected detector');

    $editor->cmd_set_theme_dark();
    is($editor->{prefs}->theme(), 'dark', 'Pref is explicit dark');
    is($editor->{theme}->name(), 'dark', 'Theme is dark');

    $editor->cmd_set_theme_light();
    is($editor->{prefs}->theme(), 'light', 'Pref is explicit light');
    is($editor->{theme}->name(), 'light', 'Theme is light');
};

subtest 'ctrl-T in auto mode switches to the explicit opposite and leaves auto' => sub {
    # Documented design: ^T always means "give me the other look right
    # now". Since that sets an explicit dark/light preference, it
    # necessarily leaves 'auto' mode — re-entering auto requires the
    # dedicated "Theme: Auto" palette command (cmd_set_theme_auto).
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
        prefs => Zepto::Preferences->new(theme => 'auto'),
        theme_detect_fn => sub { return 'dark'; },  # system is dark
    );

    is($editor->{prefs}->theme(), 'auto', 'Starts in auto');
    is($editor->{theme}->name(), 'dark', 'Auto resolved to dark (system is dark)');

    $editor->cmd_toggle_theme();
    is($editor->{prefs}->theme(), 'light', 'ctrl-T set explicit light (opposite of effective)');
    is($editor->{theme}->name(), 'light', 'Theme is now light');

    $editor->cmd_toggle_theme();
    is($editor->{prefs}->theme(), 'dark', 'Second ctrl-T set explicit dark');
    is($editor->{theme}->name(), 'dark', 'Theme is dark');
};

subtest '_maybe_poll_system_theme is a no-op unless pref is auto' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $detect_calls = 0;
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
        theme_detect_fn => sub { $detect_calls++; return 'light'; },
        theme_poll_supported_fn => sub { return 1; },
    );
    $editor->{_theme_poll_last} = 0;  # bypass debounce

    is($editor->_maybe_poll_system_theme(), 0, 'No-op: pref is explicit dark, not auto');
    is($detect_calls, 0, 'Detector never invoked');
};

subtest '_maybe_poll_system_theme is a no-op when polling is unsupported' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $detect_calls = 0;
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
        prefs => Zepto::Preferences->new(theme => 'auto'),
        theme_detect_fn => sub { $detect_calls++; return 'light'; },
        theme_poll_supported_fn => sub { return 0; },  # e.g. Linux without gsettings
    );
    $editor->{_theme_poll_last} = 0;  # bypass debounce
    $detect_calls = 0;  # constructor's own startup resolution doesn't count

    is($editor->_maybe_poll_system_theme(), 0, 'No-op: platform does not support cheap polling');
    is($detect_calls, 0, 'Detector not invoked by the poll itself');
};

subtest '_maybe_poll_system_theme respects the debounce interval' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $detect_calls = 0;
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
        prefs => Zepto::Preferences->new(theme => 'auto'),
        theme_detect_fn => sub { $detect_calls++; return 'light'; },
        theme_poll_supported_fn => sub { return 1; },
    );
    # Constructor already ran one resolution; _theme_poll_last was just
    # set to "now" — a poll attempted immediately after must be skipped.
    $detect_calls = 0;  # constructor's own startup resolution doesn't count
    is($editor->_maybe_poll_system_theme(), 0, 'Skipped: debounce interval has not elapsed');
    is($detect_calls, 0, 'Detector not invoked again within the interval');
};

subtest '_maybe_poll_system_theme swaps the theme when the system changed' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
        prefs => Zepto::Preferences->new(theme => 'auto'),
        theme_detect_fn => sub { return 'dark'; },  # matches construction-time result
        theme_poll_supported_fn => sub { return 1; },
    );
    is($editor->{theme}->name(), 'dark', 'Starts dark');

    # Simulate the system flipping to light and enough time passing
    $editor->{_theme_detect_fn} = sub { return 'light'; };
    $editor->{_theme_poll_last} = 0;

    is($editor->_maybe_poll_system_theme(), 1, 'Poll detected a change and reports it');
    is($editor->{theme}->name(), 'light', 'Theme swapped live to light');

    # A second immediate poll (still light) reports no change
    $editor->{_theme_poll_last} = 0;
    is($editor->_maybe_poll_system_theme(), 0, 'No change reported when system theme is unchanged');
};

# ============================================================================
# Preference toggles/settings added for persistent-config-file audit
# (tab_width, soft_tabs, auto_indent, mouse, search_wrap, markdown_tables)
# ============================================================================
subtest 'Tab width setting via footer input' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{prefs}->tab_width(), 4, 'Default tab width');

    $editor->cmd_set_tab_width();
    ok($editor->{footer_input}, 'Footer input opened');
    is($editor->{footer_input}->{widget}->value(), '4', 'Prefilled with current value');

    $editor->{footer_input}->{on_submit}->('2');
    is($editor->{prefs}->tab_width(), 2, 'Tab width updated to 2');

    # Invalid input is rejected and does not change the preference
    $editor->cmd_set_tab_width();
    $editor->{footer_input}->{on_submit}->('abc');
    is($editor->{prefs}->tab_width(), 2, 'Non-numeric input rejected');
    ok($editor->{message_is_error}, 'Error message flagged');

    $editor->cmd_set_tab_width();
    $editor->{footer_input}->{on_submit}->('0');
    is($editor->{prefs}->tab_width(), 2, 'Out-of-range (0) input rejected');

    $editor->cmd_set_tab_width();
    $editor->{footer_input}->{on_submit}->('17');
    is($editor->{prefs}->tab_width(), 2, 'Out-of-range (17) input rejected');

    $editor->cmd_set_tab_width();
    $editor->{footer_input}->{on_submit}->('8');
    is($editor->{prefs}->tab_width(), 8, 'Valid input (8) accepted');
};

subtest 'Soft tabs toggle' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{prefs}->soft_tabs(), 1, 'Default soft_tabs is on');
    $editor->cmd_toggle_soft_tabs();
    ok(!$editor->{prefs}->soft_tabs(), 'Soft tabs toggled off');
    $editor->cmd_toggle_soft_tabs();
    is($editor->{prefs}->soft_tabs(), 1, 'Soft tabs toggled back on');
};

subtest 'Auto indent toggle' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{prefs}->auto_indent(), 1, 'Default auto_indent is on');
    $editor->cmd_toggle_auto_indent();
    ok(!$editor->{prefs}->auto_indent(), 'Auto indent toggled off');
    $editor->cmd_toggle_auto_indent();
    is($editor->{prefs}->auto_indent(), 1, 'Auto indent toggled back on');
};

subtest 'Mouse toggle' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{prefs}->mouse_enabled(), 1, 'Default mouse_enabled is on');
    $editor->cmd_toggle_mouse();
    ok(!$editor->{prefs}->mouse_enabled(), 'Mouse toggled off');
    ok(!$term->is_mouse_enabled(), 'Terminal mouse mode disabled');

    $editor->cmd_toggle_mouse();
    is($editor->{prefs}->mouse_enabled(), 1, 'Mouse toggled back on');
    ok($term->is_mouse_enabled(), 'Terminal mouse mode re-enabled');
};

subtest 'Search wrap toggle' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{prefs}->search_wrap(), 1, 'Default search_wrap is on');
    $editor->cmd_toggle_search_wrap();
    ok(!$editor->{prefs}->search_wrap(), 'Search wrap toggled off');
    $editor->cmd_toggle_search_wrap();
    is($editor->{prefs}->search_wrap(), 1, 'Search wrap toggled back on');
};

subtest 'Markdown table rendering toggle' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{prefs}->render_markdown_tables(), 1, 'Default render_markdown_tables is on');
    $editor->cmd_toggle_markdown_tables();
    ok(!$editor->{prefs}->render_markdown_tables(), 'Markdown tables toggled off');
    $editor->cmd_toggle_markdown_tables();
    is($editor->{prefs}->render_markdown_tables(), 1, 'Markdown tables toggled back on');
};

subtest 'Auto pairs toggle' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{prefs}->auto_pairs(), 1, 'Default auto_pairs is on');
    $editor->cmd_toggle_auto_pairs();
    ok(!$editor->{prefs}->auto_pairs(), 'Auto pairs toggled off');
    is($editor->{message}, 'Auto Pairs: OFF', 'Toggle-off status message');
    $editor->cmd_toggle_auto_pairs();
    is($editor->{prefs}->auto_pairs(), 1, 'Auto pairs toggled back on');
    is($editor->{message}, 'Auto Pairs: ON', 'Toggle-on status message');
};

subtest 'Restore session toggle' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    is($editor->{prefs}->restore_session(), 1, 'Default restore_session is on');
    $editor->cmd_toggle_restore_session();
    ok(!$editor->{prefs}->restore_session(), 'Restore session toggled off');
    is($editor->{message}, 'Restore Session on Startup: OFF', 'Toggle-off status message');
    $editor->cmd_toggle_restore_session();
    is($editor->{prefs}->restore_session(), 1, 'Restore session toggled back on');
    is($editor->{message}, 'Restore Session on Startup: ON', 'Toggle-on status message');
};

subtest 'Autocomplete toggle' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    # Substitute a fake completion controller so we can observe dismiss()
    # being called (only) when the toggle turns auto-complete OFF.
    $editor->{_completion} = Test::FakeCompletion->new();

    is($editor->{prefs}->auto_complete(), 1, 'Default auto_complete is on');
    $editor->cmd_toggle_autocomplete();
    ok(!$editor->{prefs}->auto_complete(), 'Autocomplete toggled off');
    is($editor->{message}, 'Auto Complete: OFF', 'Toggle-off status message');
    is($editor->{_completion}->{dismiss_count}, 1, 'Completion dismissed when turned off');

    $editor->cmd_toggle_autocomplete();
    is($editor->{prefs}->auto_complete(), 1, 'Autocomplete toggled back on');
    is($editor->{message}, 'Auto Complete: ON', 'Toggle-on status message');
    is($editor->{_completion}->{dismiss_count}, 1, 'Completion not dismissed again when turned on');
};

subtest 'Cursor clamp after external reload' => sub {
    my $term = mock_terminal();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    my $filename = create_temp_file("line0\nline1\nline2\nline3\nline4\n");
    my ($doc, $view) = setup_editor_doc($editor, $filename);

    # Cursor sits past where a shrunk file will still have content.
    $view->set_cursor(4, 3);

    # Shrink the file on disk (fewer lines, shorter last line) and reload —
    # this is what _check_external_file_changes does before restoring the
    # cursor via the shared _restore_clamped_cursor helper.
    open my $fh, '>', $filename or die "Cannot write $filename: $!";
    print $fh "ab\ncd\n";
    close $fh;
    $doc->reload_from_disk();

    $editor->_restore_clamped_cursor($view, $doc, 4, 3);

    is($view->cursor_line(), 1, 'Cursor line clamped to new last line');
    is($view->cursor_col(), 2, 'Cursor col clamped to new (shorter) line length');

    # A position still within the shrunk document's bounds is left as-is.
    open my $fh2, '>', $filename or die "Cannot write $filename: $!";
    print $fh2 "abcdef\nghijkl\n";
    close $fh2;
    $doc->reload_from_disk();

    $editor->_restore_clamped_cursor($view, $doc, 0, 3);
    is($view->cursor_line(), 0, 'In-bounds line left unchanged');
    is($view->cursor_col(), 3, 'In-bounds col left unchanged');
};

subtest 'New preference toggles persist across StateStore-backed instances' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store1 = Zepto::StateStore->new(base_dir => $tmpdir);
    my $editor1 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store1);

    $editor1->cmd_set_tab_width();
    $editor1->{footer_input}->{on_submit}->('2');
    $editor1->cmd_toggle_soft_tabs();
    $editor1->cmd_toggle_auto_indent();
    $editor1->cmd_toggle_mouse();
    $editor1->cmd_toggle_search_wrap();
    $editor1->cmd_toggle_markdown_tables();

    my $store2 = Zepto::StateStore->new(base_dir => $tmpdir);
    my $editor2 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store2);

    is($editor2->{prefs}->tab_width(), 2, 'Tab width persisted');
    ok(!$editor2->{prefs}->soft_tabs(), 'Soft tabs persisted');
    ok(!$editor2->{prefs}->auto_indent(), 'Auto indent persisted');
    ok(!$editor2->{prefs}->mouse_enabled(), 'Mouse enabled persisted');
    ok(!$editor2->{prefs}->search_wrap(), 'Search wrap persisted');
    ok(!$editor2->{prefs}->render_markdown_tables(), 'Markdown tables persisted');
};

# ============================================================================
# Search state
# ============================================================================
subtest 'Search state' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    is($editor->{search_term}, '', 'Search term empty');
    is($editor->{search_replace}, '', 'Replace term empty');

    $editor->{search_term} = 'find me';
    is($editor->{search_term}, 'find me', 'Search term set');
};

# ============================================================================
# Integration: Init with existing file
# ============================================================================
subtest 'Init with existing file' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\n");

    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    # Can't call init() without real terminal, but test file path
    is($editor->{initial_file}, $filename, 'File path stored');
};

# ============================================================================
# Ctrl+char handling
# ============================================================================
subtest 'Ctrl char mapping' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Test content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    # Initialize document and view manually for testing
    setup_editor_doc($editor, $filename);

    # Test undo when nothing to undo — verify document unchanged
    my $original_text = $editor->active_doc()->text();
    $editor->cmd_undo();
    like($editor->{message}, qr/undo/i, 'Undo message when nothing to undo');
    is($editor->active_doc()->text(), $original_text, 'Document unchanged after empty undo');

    # Test redo when nothing to redo — verify document unchanged
    $editor->cmd_redo();
    like($editor->{message}, qr/redo/i, 'Redo message when nothing to redo');
    is($editor->active_doc()->text(), $original_text, 'Document unchanged after empty redo');

    # Make an edit, then undo — verify document actually reverts
    $editor->active_doc()->insert(0, 'XYZ');
    my $edited_text = $editor->active_doc()->text();
    isnt($edited_text, $original_text, 'Edit changed document');

    $editor->cmd_undo();
    is($editor->active_doc()->text(), $original_text, 'Undo reverted the edit');

    # Redo — verify document restores the edit
    $editor->cmd_redo();
    is($editor->active_doc()->text(), $edited_text, 'Redo restored the edit');
};

# ============================================================================
# Insert and delete with selection
# ============================================================================
subtest 'Delete selection' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Create selection
    $editor->active_view()->move_right() for (1..5);  # Move to space after Hello
    $editor->active_view()->move_right(1) for (1..6); # Select " World"

    ok($editor->active_view()->has_selection(), 'Selection active');

    $editor->delete_selection();
    ok(!$editor->active_view()->has_selection(), 'Selection cleared');
    is($editor->active_doc()->text(), 'Hello', 'Selection deleted');
};

# ============================================================================
# Indent/unindent
# ============================================================================
subtest 'Indent' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->do_indent();
    like($editor->active_doc()->text(), qr/^    line/, 'Line indented with spaces');
};

subtest 'Hard tab indent' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line\n");
    my $prefs = Zepto::Preferences->new(soft_tabs => 0);
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
        prefs => $prefs,
    );

    setup_editor_doc($editor, $filename);

    $editor->do_indent();
    like($editor->active_doc()->text(), qr/^\tline/, 'Line indented with tab');
};

subtest 'Indent preserves selection' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line1\nline2\nline3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Select lines 1-2 (0-indexed: lines 0-1)
    $editor->active_view()->set_cursor(0, 0, 0);
    $editor->active_view()->set_cursor(1, 5, 1);  # Select to end of "line2"

    ok($editor->active_view()->has_selection(), 'Selection active before indent');

    $editor->do_indent();

    ok($editor->active_view()->has_selection(), 'Selection preserved after indent');
    like($editor->active_doc()->text(), qr/^    line1\n    line2\n/, 'Lines indented');
};

subtest 'Unindent preserves selection' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("    line1\n    line2\nline3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Select lines 1-2 (0-indexed: lines 0-1)
    $editor->active_view()->set_cursor(0, 4, 0);  # Start at "l" in "line1"
    $editor->active_view()->set_cursor(1, 9, 1);  # Select to end of "    line2"

    ok($editor->active_view()->has_selection(), 'Selection active before unindent');

    $editor->do_unindent();

    ok($editor->active_view()->has_selection(), 'Selection preserved after unindent');
    like($editor->active_doc()->text(), qr/^line1\nline2\n/, 'Lines unindented');
};

# ============================================================================
# Move/duplicate lines
# ============================================================================
subtest 'Move line down' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\nccc\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Cursor on first line
    is($editor->active_view()->cursor_line(), 0, 'Start on line 0');

    $editor->do_move_line_down();

    is($editor->active_doc()->text(), "bbb\naaa\nccc", 'Line moved down');
    is($editor->active_view()->cursor_line(), 1, 'Cursor follows moved line');
};

subtest 'Move line up' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\nccc\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Move cursor to second line
    $editor->active_view()->move_down();
    is($editor->active_view()->cursor_line(), 1, 'Start on line 1');

    $editor->do_move_line_up();

    is($editor->active_doc()->text(), "bbb\naaa\nccc", 'Line moved up');
    is($editor->active_view()->cursor_line(), 0, 'Cursor follows moved line');
};

subtest 'Move line at boundary is no-op' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Try to move first line up - should be no-op
    $editor->do_move_line_up();
    is($editor->active_doc()->text(), "aaa\nbbb", 'First line stays put');

    # Move to last line, try to move down - should be no-op
    $editor->active_view()->move_down();
    $editor->do_move_line_down();
    is($editor->active_doc()->text(), "aaa\nbbb", 'Last line stays put');
};

subtest 'Move multiple selected lines' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\nccc\nddd\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Select lines 1-2 (bbb, ccc)
    $editor->active_view()->move_down();  # Line 1
    $editor->active_view()->set_cursor(1, 0, 0);
    $editor->active_view()->set_cursor(2, 3, 1);  # Partial selection of line 2

    $editor->do_move_line_down();

    is($editor->active_doc()->text(), "aaa\nddd\nbbb\nccc", 'Selected lines moved down');
    ok($editor->active_view()->has_selection(), 'Selection preserved');
};

subtest 'Duplicate line down' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->do_duplicate_line_down();

    is($editor->active_doc()->text(), "aaa\naaa\nbbb", 'Line duplicated below');
    is($editor->active_view()->cursor_line(), 1, 'Cursor on new duplicate');
};

subtest 'Duplicate line up' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->active_view()->move_down();  # Line 1

    $editor->do_duplicate_line_up();

    is($editor->active_doc()->text(), "aaa\nbbb\nbbb", 'Line duplicated above');
    is($editor->active_view()->cursor_line(), 1, 'Cursor on new duplicate');
};

subtest 'Alt+U keybinding dispatches to Duplicate Down' => sub {
    # bugs.md P2 "Shortcut key for Duplicate Down": Ctrl+Shift+D was
    # considered but rejected because classic terminals deliver
    # Ctrl+letter as a single control byte (no way to carry Shift), so
    # Alt+U was bound instead — verify the raw ESC+'u' sequence a
    # terminal actually sends for Alt+U reaches do_duplicate_line_down.
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->handle_input("\x1bu");  # ESC + 'u' = Alt+U

    is($editor->active_doc()->text(), "aaa\naaa\nbbb", 'Alt+U duplicated line below');
    is($editor->active_view()->cursor_line(), 1, 'Cursor on new duplicate');
};

# ============================================================================
# Built-in Text Transforms (bugs.md P3 "Transform (Alt+T) is shell-pipe only")
#
# Note: Document->load() strips the file's trailing newline for in-memory
# editing (Document->save() adds it back per POSIX convention — see
# Document.pm "Strip trailing newline for editing"). So text() on a
# create_temp_file()-loaded document never ends with "\n" regardless of
# what was on disk. Tests that need a real embedded "\n" inside the text
# under test build the Document directly via Zepto::Document->new(text
# => ...), which stores content as-is with no stripping.
# ============================================================================
subtest 'cmd_transform_uppercase on selection' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("hello world\nother line\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $view = $editor->active_view();
    $view->set_cursor(0, 0, 0);
    $view->set_cursor(0, 5, 1);  # select "hello"

    $editor->cmd_transform_uppercase();

    is($editor->active_doc()->text(), "HELLO world\nother line", 'Only selection uppercased');
};

subtest 'cmd_transform_lowercase on whole document when nothing selected' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("HELLO WORLD\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    ok(!$editor->active_view()->has_selection(), 'No selection to start');
    $editor->cmd_transform_lowercase();

    is($editor->active_doc()->text(), 'hello world', 'Whole document lowercased (auto-select-all)');
};

subtest 'cmd_transform_uppercase is a no-op (no undo entry) when already uppercase' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("ALREADY UPPER\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $doc = $editor->active_doc();
    my $version_before = $doc->content_version();
    $editor->cmd_transform_uppercase();

    is($doc->text(), 'ALREADY UPPER', 'Text unchanged');
    is($doc->content_version(), $version_before, 'No-op transform does not bump content_version (no undo entry)');
};

subtest 'cmd_transform_sort_lines sorts alphabetically' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("banana\napple\ncherry\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_transform_sort_lines();

    is($editor->active_doc()->text(), "apple\nbanana\ncherry", 'Lines sorted');
};

subtest 'cmd_transform_sort_lines preserves trailing newline on a partial selection' => sub {
    my $term = mock_terminal();
    # Built directly (not via create_temp_file/load), so the embedded "\n"
    # characters are real — this is what a partial, mid-document selection
    # actually looks like in memory.
    my $doc = Zepto::Document->new(text => "banana\napple\ncherry\n");
    my $view = Zepto::View->new(document => $doc);
    my $term2 = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term2);
    my $find_engine = Zepto::FindEngine->new(document => $doc);
    my $highlighter = Zepto::Highlighter->new();
    $editor->{tab_manager}->add_tab(
        document => $doc, view => $view, find_engine => $find_engine,
        highlighter => $highlighter, file_path => undef,
    );

    # Select "banana\napple\n" (first two lines, including their trailing
    # newlines) — leaves "cherry\n" out of the selection entirely.
    $view->set_cursor(0, 0, 0);
    $view->set_cursor(2, 0, 1);

    $editor->cmd_transform_sort_lines();

    is($doc->text(), "apple\nbanana\ncherry\n",
       'Selected lines sorted with trailing newline preserved; unselected "cherry" untouched');
};

subtest 'cmd_transform_reverse_lines reverses line order' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("one\ntwo\nthree\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_transform_reverse_lines();

    is($editor->active_doc()->text(), "three\ntwo\none", 'Line order reversed');
};

subtest 'cmd_transform_unique_lines keeps first occurrence, preserves order' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("banana\napple\ncherry\napple\nbanana\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_transform_unique_lines();

    is($editor->active_doc()->text(), "banana\napple\ncherry",
       'Duplicates removed, first-occurrence order preserved (not re-sorted)');
};

subtest 'Built-in transforms are undoable in one step' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("banana\napple\ncherry\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $doc = $editor->active_doc();
    my $original = $doc->text();

    $editor->cmd_transform_sort_lines();
    isnt($doc->text(), $original, 'Text changed after sort');

    $doc->undo();
    is($doc->text(), $original, 'Single undo restores original order');
};

subtest 'Built-in transforms never shell out (pure Perl, no injection risk)' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $marker = "$tmpdir/should_never_run";

    my $term = mock_terminal();
    my $filename = create_temp_file("foo; touch $marker; echo hi\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_transform_uppercase();

    is($editor->active_doc()->text(), 'FOO; TOUCH ' . uc($marker) . '; ECHO HI',
       'Shell-metacharacter line treated as literal text, uppercased in place');
    ok(!-e $marker, 'No command was ever executed');
};

# ============================================================================
# Copy/paste
# ============================================================================
subtest 'Copy and paste' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Select "Hello"
    $editor->active_view()->move_right(1) for (1..5);

    $editor->cmd_copy();
    is($editor->{clipboard}, 'Hello', 'Text copied');

    # Move to end
    $editor->active_view()->move_to_document_end();
    $editor->active_view()->move_to_line_end();

    $editor->cmd_paste();
    is($editor->active_doc()->text(), 'Hello WorldHello', 'Text pasted');
};

subtest 'Copy without selection copies current line' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line one\nline two\nline three\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Position cursor on line two, no selection
    $editor->active_view()->move_down();
    ok(!$editor->active_view()->has_selection(), 'No selection initially');

    $editor->cmd_copy();

    # Should have selected and copied the entire line including newline
    ok($editor->active_view()->has_selection(), 'Line is now selected');
    is($editor->{clipboard}, "line two\n", 'Entire line copied including newline');
    is($editor->active_view()->cursor_line(), 1, 'Cursor stays on same line');
    is($editor->active_view()->cursor_col(), 8, 'Cursor at end of line');
};

subtest 'Cut without selection cuts current line' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line one\nline two\nline three\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Position cursor on line two, no selection
    $editor->active_view()->move_down();
    ok(!$editor->active_view()->has_selection(), 'No selection initially');

    $editor->cmd_cut();

    # Line should be cut
    is($editor->{clipboard}, "line two\n", 'Entire line cut including newline');
    is($editor->active_doc()->text(), "line one\nline three", 'Line removed from document');
};

# ============================================================================
# Find functionality
#
# These subtests exercise cmd_find_next/cmd_find_prev — the real,
# reachable commands wired to keys and the command palette. They used to
# call now-deleted do_find_next/do_find_prev, an old, unreachable
# text/index-based implementation that scanned $doc->text() directly with
# index()/rindex() and set a status message on every call (see bugs.md
# "do_find_next/do_find_prev are 77 lines of dead production code"). The
# real cmd_find_next/cmd_find_prev instead call enter_find_mode() (which
# re-anchors to the match nearest the cursor via FindEngine on every
# single call, and does NOT set a "Found"/"Not found" status message) and
# then _find_navigate() to step from there — a meaningfully different
# match-selection algorithm from the deleted dead code, so the assertions
# below were re-derived against the real command path rather than
# transplanted unchanged. Multi-match stepping and wrap-around are
# covered in more depth directly against _find_navigate() in tests/find.t
# ('Navigate to next match', 'Navigate wraps at end', 'Navigate wraps at
# start', 'Navigate with no matches') — these editor.t subtests instead
# confirm the cmd_find_next/cmd_find_prev entry points themselves
# actually invoke that machinery and land on a real match.
# ============================================================================
subtest 'Find next' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("foo bar foo baz\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);
    $editor->{search_term} = 'foo';

    $editor->cmd_find_next();

    # Cursor starts at 0,0 (on the first "foo"); enter_find_mode() anchors
    # to the match at-or-after the cursor (the first "foo", col 0) and
    # _find_navigate(1) then steps one match forward, landing on the
    # second "foo" (cols 8-11).
    ok($editor->active_view()->has_selection(), 'Match selected');
    my ($sl, $sc, $el, $ec) = $editor->active_view()->selection();
    is($sc, 8, 'Selected the next match after the cursor');
};

subtest 'Find not found' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    my (undef, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(0, 3);
    $editor->{search_term} = 'xyz';

    $editor->cmd_find_next();

    # No match exists, so no selection is made and the cursor is left
    # exactly where it was (unlike the deleted dead code, the real
    # command path doesn't set a "Not found" status message).
    ok(!$view->has_selection(), 'No selection when term is not found');
    is($view->cursor_line(), 0, 'Cursor line unchanged');
    is($view->cursor_col(), 3, 'Cursor col unchanged');
};

subtest 'Find prev selects a match' => sub {
    my $term = mock_terminal();
    # Content: "foo bar foo baz foo" — matches at col 0, col 8, col 16
    my $filename = create_temp_file("foo bar foo baz foo\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    my (undef, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(0, 19);  # near the end of the line
    $editor->{search_term} = 'foo';

    $editor->cmd_find_prev();

    ok($view->has_selection(), 'A match is selected');
    my ($sl, $sc, $el, $ec) = $view->selection();
    is($sc, 8, 'cmd_find_prev selected the "foo" at column 8');
};

subtest 'Find next falls back to cmd_find when no search term is set' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("foo bar foo baz\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);
    $editor->{search_term} = '';

    $editor->cmd_find_next();

    is($editor->{state}, 'find', 'Opens the find bar instead of navigating');
};

# ============================================================================
# Mouse drag selection
# ============================================================================
subtest 'Mouse drag selection' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    # Content: "Hello World Test" - "World" is at columns 6-10
    my $filename = create_temp_file("Hello World Test\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->active_doc()->line_count());

    # Simulate press at column 6 (start of "World")
    # Row 4 is the first text line (after menu bar on 1, tab bar on 2, ruler bar on 3)
    # Terminal coordinates are 1-indexed, so x = gutter_width + col + 1
    my $x_start = $gutter_width + 6 + 1;  # gutter + col 6 + 1 for 1-indexed
    my $press = { type => 'mouse', action => 'press', x => $x_start, y => 4, modifiers => [] };
    $editor->handle_mouse_event($press);

    ok(!$editor->active_view()->has_selection(), 'No selection after press');
    is($editor->active_view()->cursor_col(), 6, 'Cursor at column 6 after press');

    # Simulate drag to column 11 (end of "World")
    my $x_end = $gutter_width + 11 + 1;  # gutter + col 11 + 1 for 1-indexed
    my $drag = { type => 'mouse', action => 'drag', x => $x_end, y => 4, modifiers => [] };
    $editor->handle_mouse_event($drag);

    ok($editor->active_view()->has_selection(), 'Selection exists after drag');
    my ($sl, $sc, $el, $ec) = $editor->active_view()->selection();
    is($sc, 6, 'Selection starts at column 6');
    is($ec, 11, 'Selection ends at column 11');
    is($editor->active_view()->selected_text(), 'World', 'Selected text is "World"');
};

# ============================================================================
# Double-click word selection and triple-click line selection
# ============================================================================
subtest 'Double-click selects word, triple-click selects line' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World Test\nSecond line here\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->active_doc()->line_count());

    # Tab bar = row 1, ruler = row 2, text starts at row 3
    my $text_y = 3;

    # Double-click on "World" (col 6, which is 'W')
    my $x = $gutter_width + 6 + 1;

    # First click
    my $press1 = { type => 'mouse', action => 'press', x => $x, y => $text_y, button => 0, modifiers => [] };
    $editor->handle_mouse_event($press1);
    my $release1 = { type => 'mouse', action => 'release', x => $x, y => $text_y, button => 0, modifiers => [] };
    $editor->handle_mouse_event($release1);

    # Second click (double-click) — use handle_event to go through the standard path
    my $press2 = { type => 'mouse', action => 'press', x => $x, y => $text_y, button => 0, modifiers => [] };
    $editor->handle_mouse_event($press2);

    ok($editor->active_view()->has_selection(), 'Double-click creates selection');
    if ($editor->active_view()->has_selection()) {
        is($editor->active_view()->selected_text(), 'World', 'Double-click selects word "World"');
    }

    # Triple-click — select entire line
    my $press3 = { type => 'mouse', action => 'press', x => $x, y => $text_y, button => 0, modifiers => [] };
    $editor->handle_mouse_event($press3);

    ok($editor->active_view()->has_selection(), 'Triple-click creates selection');
    if ($editor->active_view()->has_selection()) {
        my $sel = $editor->active_view()->selected_text();
        # Triple-click selects entire line including newline
        like($sel, qr/Hello World Test/, 'Triple-click selects entire line content');
    }
};

# ============================================================================
# Go to line
# ============================================================================
subtest 'Goto line logic' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Simulate goto line 2
    $editor->active_view()->set_cursor(1, 0);  # Line 2 (0-indexed)
    is($editor->active_view()->cursor_line(), 1, 'Cursor on line 2');
};

subtest 'Goto line uses footer input' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->cmd_goto_line();

    is($editor->{state}, 'footer_input', 'Goto line uses footer input, not dialog');
    ok($editor->{footer_input}, 'Footer input is set');
    is($editor->{footer_input}{id}, 'goto_line', 'Footer input has goto_line id');
    ok($editor->{footer_input}{hint}, 'Footer input has hint');
    like($editor->{footer_input}{hint}, qr/line.*:col/i, 'Hint mentions line:col syntax');
};

subtest 'Goto line parses line number' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->cmd_goto_line();
    $editor->handle_input('3');
    $editor->handle_input("\r");  # Enter

    is($editor->active_view()->cursor_line(), 2, 'Line 3 is 0-indexed line 2');
    is($editor->active_view()->cursor_col(), 0, 'Column is 0');
};

subtest 'Goto line 0 goes to line 1' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Start on line 2
    $editor->active_view()->set_cursor(1, 3);

    $editor->cmd_goto_line();
    $editor->handle_input('0');
    $editor->handle_input("\r");

    is($editor->active_view()->cursor_line(), 0, 'Line 0 input goes to first line');
    is($editor->active_view()->cursor_col(), 0, 'Column is 0');
};

subtest 'Goto line:col parses column' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2 with more text\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->cmd_goto_line();
    $editor->handle_input('2:10');
    $editor->handle_input("\r");

    is($editor->active_view()->cursor_line(), 1, 'Line 2 is 0-indexed line 1');
    is($editor->active_view()->cursor_col(), 9, 'Column 10 is 0-indexed column 9');
};

subtest 'Goto :col jumps to column on current line' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2 with more text\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Start on line 2 (0-indexed: 1), column 0
    $editor->active_view()->set_cursor(1, 0);

    $editor->cmd_goto_line();
    $editor->handle_input(':15');
    $editor->handle_input("\r");

    is($editor->active_view()->cursor_line(), 1, 'Stays on current line');
    is($editor->active_view()->cursor_col(), 14, 'Column 15 is 0-indexed column 14');
};

subtest 'Goto line clamps to valid range' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Go to line way beyond end
    $editor->cmd_goto_line();
    $editor->handle_input('999');
    $editor->handle_input("\r");

    my $max_line = $editor->active_doc()->line_count() - 1;
    is($editor->active_view()->cursor_line(), $max_line, 'Line clamped to max');
};

subtest 'Goto line:col clamps column to line length' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Short\nLine 2\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->cmd_goto_line();
    $editor->handle_input('1:999');
    $editor->handle_input("\r");

    is($editor->active_view()->cursor_line(), 0, 'On line 1');
    is($editor->active_view()->cursor_col(), 5, 'Column clamped to line length (5 chars in "Short")');
};

# ============================================================================
# Stability: Editor should not quit unexpectedly
# ============================================================================
subtest 'Editor does not quit on empty input' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Test content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Simulate handling empty input (what happens on timeout)
    $editor->handle_input('');
    is($editor->{state}, 'editing', 'Still editing after empty input');

    # Simulate handling whitespace
    $editor->handle_input(' ');
    is($editor->{state}, 'editing', 'Still editing after space');

    # Simulate carriage return (Enter key) - CR is Enter, LF is Ctrl+J
    $editor->handle_input("\r");
    is($editor->{state}, 'editing', 'Still editing after Enter (CR)');
};

subtest 'Editor does not quit on escape sequences' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Test\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Arrow keys
    $editor->handle_input("\x1b[A");  # Up
    is($editor->{state}, 'editing', 'Still editing after up arrow');

    $editor->handle_input("\x1b[B");  # Down
    is($editor->{state}, 'editing', 'Still editing after down arrow');

    # Mouse events (SGR format)
    $editor->handle_input("\x1b[<0;10;5M");  # Mouse press
    is($editor->{state}, 'editing', 'Still editing after mouse event');

    # Lone escape with nothing to cancel stays in editing state (no palette fallback)
    $editor->handle_input("\x1b");
    $editor->flush_pending_input();
    is($editor->{state}, 'editing', 'Lone escape stays in editing state');
};

subtest 'Only quit commands trigger quit' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Test\n");

    # Test various control characters that should NOT quit
    # Each test gets a fresh editor since some Ctrl keys open dialogs
    # Skip 17 (Ctrl+Q) and 23 (Ctrl+W = save and quit)
    for my $ctrl (1..16, 18..22, 24..26) {
        my $editor = Zepto::Editor->new(
            terminal => $term,
            file => $filename,
        );
        setup_editor_doc($editor, $filename);

        my $char = chr($ctrl);
        $editor->handle_input($char);
        isnt($editor->{state}, 'quit', "Ctrl+" . chr(ord('a') + $ctrl - 1) . " doesn't quit");
    }

    # Test Ctrl+Q (chr(17)) - should trigger quit on clean document
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );
    setup_editor_doc($editor, $filename);

    $editor->handle_input("\x11");  # Ctrl+Q
    is($editor->{state}, 'quit', 'Ctrl+Q triggers quit');

    # Test Ctrl+W (chr(23)) - save and quit on clean document
    $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );
    setup_editor_doc($editor, $filename);

    $editor->handle_input("\x17");  # Ctrl+W
    is($editor->{state}, 'quit', 'Ctrl+W triggers save and quit');
};

subtest 'Quit requires confirmation on dirty document' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Test\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Make document dirty
    $editor->active_doc()->insert(0, 'x');
    ok($editor->active_doc()->is_dirty(), 'Document is dirty');

    # Ctrl+Q on dirty doc should show save prompt
    $editor->handle_input("\x11");
    is($editor->{state}, 'prompt', 'Ctrl+Q on dirty doc shows prompt');
    ok($editor->{prompt}, 'Prompt is set');
    like($editor->{prompt}{text}, qr/save changes/i, 'Prompt asks about saving');

    # Pressing 'n' (No) should quit without saving
    $editor->handle_input("n");
    is($editor->{state}, 'quit', 'Pressing No quits');
};

# ============================================================================
# New File (Ctrl+N)
# ============================================================================
subtest 'New file on clean document' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Original content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Document is clean, should create new immediately
    $editor->cmd_new_file();

    is($editor->active_doc()->text(), '', 'Document is now empty');
    is($editor->active_file_path(), undef, 'File path cleared');
};

subtest 'New file on dirty document creates new tab' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Original\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Make dirty
    $editor->active_doc()->insert(0, 'x');
    ok($editor->active_doc()->is_dirty(), 'Document is dirty');

    $editor->cmd_new_file();

    # With tabs, new file creates a new tab without prompting
    is($editor->{state}, 'editing', 'Still in editing state');
    is($editor->active_doc()->text(), '', 'New tab document is empty');
    is($editor->{tab_manager}->tab_count(), 2, 'Two tabs open');
};

# ============================================================================
# Open File (Ctrl+O)
# ============================================================================
subtest 'Open file on clean document shows picker' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->cmd_open_file();

    is($editor->{state}, 'palette', 'State is palette');
    is($editor->{palette_mode}, 'files', 'Palette mode is files');
    ok($editor->{palette_widget}, 'Palette widget created');
    ok(scalar @{$editor->{palette_filtered}} > 0, 'Palette has filtered items');
};

subtest 'Open file on dirty document opens palette picker' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Original\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Make dirty
    $editor->active_doc()->insert(0, 'x');

    $editor->cmd_open_file();

    # With tabs, open file opens palette in files mode (dirty doc stays in its tab)
    is($editor->{state}, 'palette', 'State is palette');
    is($editor->{palette_mode}, 'files', 'Palette mode is files');
};

# ============================================================================
# Prompt handling
# ============================================================================
subtest 'Prompt responds to key press' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    # Open prompt with test callback
    my $choice_made;
    $editor->open_prompt(
        text => 'Test prompt',
        options => [
            { key => 'y', label => 'Yes' },
            { key => 'n', label => 'No' },
        ],
        on_select => sub { $choice_made = shift; },
    );

    is($editor->{state}, 'prompt', 'Prompt state active');

    # Press 'y'
    $editor->handle_input('y');

    is($choice_made, 'y', 'Callback received correct choice');
    is($editor->{state}, 'editing', 'Back to editing state');
};

subtest 'Prompt escape cancels' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    my $choice_made = 'not_called';
    $editor->open_prompt(
        text => 'Test',
        options => [{ key => 'y', label => 'Yes' }],
        on_select => sub { $choice_made = shift; },
    );

    # Press escape
    $editor->handle_input("\e");
    $editor->flush_pending_input();

    is($choice_made, 'not_called', 'Callback not called on escape');
    is($editor->{state}, 'editing', 'Back to editing state');
};

# ============================================================================
# Palette-based file picker (Ctrl+O)
# ============================================================================
subtest 'File picker navigation' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->cmd_open_file();
    is($editor->{state}, 'palette', 'Palette open');
    is($editor->{palette_mode}, 'files', 'Files mode');

    my $initial = $editor->{palette_cursor};

    # Arrow down
    $editor->handle_input("\e[B");  # Down arrow
    is($editor->{palette_cursor}, $initial + 1, 'Down arrow moves cursor');

    # Arrow up
    $editor->handle_input("\e[A");  # Up arrow
    is($editor->{palette_cursor}, $initial, 'Up arrow moves cursor back');
};

subtest 'File picker typing filters' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->cmd_open_file();
    my $initial_count = scalar @{$editor->{palette_filtered}};

    # Type to filter — unlikely to match much
    $editor->handle_input('xyznonexistent');

    my $new_count = scalar @{$editor->{palette_filtered}};
    ok($new_count <= $initial_count, 'Typing filters results');
    is($editor->{palette_widget}->value(), 'xyznonexistent', 'Query updated');
};

subtest 'File picker escape closes palette' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);

    $editor->cmd_open_file();
    is($editor->{state}, 'palette', 'Palette open');

    # Escape closes palette
    $editor->handle_input("\e");
    $editor->flush_pending_input();
    is($editor->{state}, 'editing', 'Back to editing');

    # Re-open, type something, then escape still closes
    $editor->cmd_open_file();
    is($editor->{state}, 'palette', 'Palette re-opened');
    $editor->handle_input('t');
    ok(length($editor->{palette_widget}->value()) > 0, 'Query has content');
    $editor->handle_input("\e");
    $editor->flush_pending_input();
    is($editor->{state}, 'editing', 'Back to editing after typed query');
};

# ============================================================================
# Footer input handling (Save As in footer)
# ============================================================================
subtest 'Footer input opens and closes' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    my $submitted_value;
    $editor->open_footer_input(
        prompt => 'Test:',
        value => 'initial',
        on_submit => sub { $submitted_value = shift; },
    );

    is($editor->{state}, 'footer_input', 'State is footer_input');
    is($editor->{footer_input}{prompt}, 'Test:', 'Prompt set');
    is($editor->{footer_input}{widget}->value(), 'initial', 'Initial value set');

    $editor->close_footer_input();
    is($editor->{state}, 'editing', 'Back to editing');
    is($editor->{footer_input}, undef, 'Footer input cleared');
};

subtest 'Footer input handles typing' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->open_footer_input(prompt => 'Name:');
    is($editor->{footer_input}{widget}->value(), '', 'Value initially empty');

    # Type characters
    $editor->handle_input('a');
    is($editor->{footer_input}{widget}->value(), 'a', 'Char added');

    $editor->handle_input('bc');
    is($editor->{footer_input}{widget}->value(), 'abc', 'More chars added');

    # Backspace
    $editor->handle_input("\x7f");  # DEL/backspace
    is($editor->{footer_input}{widget}->value(), 'ab', 'Backspace works');
};

subtest 'Footer input submit calls callback' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $submitted;
    $editor->open_footer_input(
        prompt => 'Name:',
        on_submit => sub { $submitted = shift; },
    );

    $editor->handle_input('test.txt');
    $editor->handle_input("\r");  # Enter

    is($submitted, 'test.txt', 'Submit callback received value');
    is($editor->{state}, 'editing', 'Back to editing after submit');
};

subtest 'Footer input escape cancels' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $cancelled = 0;
    $editor->open_footer_input(
        prompt => 'Name:',
        on_cancel => sub { $cancelled = 1; },
    );

    $editor->handle_input('partial');
    $editor->handle_input("\e");  # Escape
    $editor->flush_pending_input();

    is($cancelled, 1, 'Cancel callback called');
    is($editor->{state}, 'editing', 'Back to editing after cancel');
};

# ============================================================================
# Palette type-to-filter
# ============================================================================
subtest 'Palette type-to-filter' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->cmd_open_palette();
    my $initial_count = scalar @{$editor->{palette_filtered}};
    ok($initial_count > 0, 'Palette has commands when opened');

    # Type a filter query
    $editor->handle_palette_event({ type => 'char', char => 's', modifiers => [] });
    $editor->handle_palette_event({ type => 'char', char => 'a', modifiers => [] });
    $editor->handle_palette_event({ type => 'char', char => 'v', modifiers => [] });
    is($editor->{palette_widget}->value(), 'sav', 'Query is "sav"');

    my $filtered_count = scalar @{$editor->{palette_filtered}};
    ok($filtered_count <= $initial_count, 'Filtered list is smaller or equal');
    ok($filtered_count > 0, 'At least one match for "sav"');
};

# ============================================================================
# Mouse button tracking (spurious drag prevention)
# ============================================================================
subtest 'Mouse button state tracking' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    is($editor->{mouse_button_down}, 0, 'Mouse button initially up');

    # Press
    my $press = { type => 'mouse', action => 'press', x => 10, y => 2, modifiers => [] };
    $editor->handle_mouse_event($press);
    is($editor->{mouse_button_down}, 1, 'Mouse button down after press');

    # Release
    my $release = { type => 'mouse', action => 'release', x => 10, y => 2, modifiers => [] };
    $editor->handle_mouse_event($release);
    is($editor->{mouse_button_down}, 0, 'Mouse button up after release');
};

subtest 'Drag without press is ignored' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->active_doc()->line_count());

    # Ensure mouse button is up
    is($editor->{mouse_button_down}, 0, 'Mouse button initially up');
    ok(!$editor->active_view()->has_selection(), 'No selection initially');

    # Send drag event without press first (spurious motion)
    my $drag = { type => 'mouse', action => 'drag', x => $gutter_width + 5, y => 2, modifiers => [] };
    $editor->handle_mouse_event($drag);

    # Should NOT create selection
    ok(!$editor->active_view()->has_selection(), 'No selection after spurious drag');
};

subtest 'Drag after press creates selection' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->active_doc()->line_count());

    # Press first
    my $press = { type => 'mouse', action => 'press', x => $gutter_width + 0, y => 2, modifiers => [] };
    $editor->handle_mouse_event($press);
    is($editor->{mouse_button_down}, 1, 'Mouse button down');

    # Then drag
    my $drag = { type => 'mouse', action => 'drag', x => $gutter_width + 5, y => 2, modifiers => [] };
    $editor->handle_mouse_event($drag);

    # Should create selection
    ok($editor->active_view()->has_selection(), 'Selection created after proper press+drag');
};

# ============================================================================
# Mouse click with tabs - cursor should account for tab display width
# ============================================================================
subtest 'Mouse click accounts for tab display width' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    # Content: "a\tb" - 'a' at doc col 0, tab at doc col 1, 'b' at doc col 2
    # With tab width 4: 'a' displays at col 0, tab expands to cols 1-3, 'b' at col 4
    my $filename = create_temp_file("a\tb\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->active_doc()->line_count());

    # Click at display column 4 (where 'b' visually appears)
    # Terminal coordinates are 1-indexed, so x = gutter_width + display_col + 1
    # Row 4 is the first text line (after menu bar on 1, tab bar on 2, ruler bar on 3)
    my $display_col = 4;  # Where 'b' appears visually
    my $x = $gutter_width + $display_col + 1;
    my $press = { type => 'mouse', action => 'press', x => $x, y => 4, modifiers => [] };
    $editor->handle_mouse_event($press);

    # Cursor should be at document column 2 (after 'a' and tab), not display column 4
    is($editor->active_view()->cursor_col(), 2, 'Cursor at doc column 2 (after a and tab), not display column 4');
};

subtest 'Mouse click in middle of tab jumps to tab position' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    # Content: "a\tb" - clicking in the middle of the tab's visual space
    my $filename = create_temp_file("a\tb\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->active_doc()->line_count());

    # Click at display column 2 (in the middle of the tab's visual space, columns 1-3)
    my $display_col = 2;
    my $x = $gutter_width + $display_col + 1;
    my $press = { type => 'mouse', action => 'press', x => $x, y => 4, modifiers => [] };
    $editor->handle_mouse_event($press);

    # Cursor should be at document column 1 (the tab character position)
    is($editor->active_view()->cursor_col(), 1, 'Clicking in tab space positions cursor at tab character');
};

# ============================================================================
# Enter key / newline insertion
# ============================================================================

# ============================================================================
# Tab bar click should unfocus file tree
# ============================================================================

subtest 'Tab bar click unfocuses file tree' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    # Open a file so we have a tab
    my $filename = create_temp_file("test content\n");
    setup_editor_doc($editor, $filename);

    # Set up file tree and focus it
    require Zepto::FileTree;
    $editor->{file_tree} = Zepto::FileTree->new(root_path => '.');
    $editor->{file_tree}->set_focused(1);
    ok($editor->{file_tree}->focused(), 'Tree starts focused');

    # Simulate tab bar click (call handle_tab_bar_click)
    # We need rendered tab bar buttons, so just call the function
    # The unfocus logic runs at the beginning of handle_tab_bar_click
    $editor->handle_tab_bar_click(50);

    ok(!$editor->{file_tree}->focused(), 'Tree unfocused after tab bar click');
};

subtest 'Clicking document area confirms preview instead of dismissing' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    # Create a file to preview
    my $filename = create_temp_file("preview content\nsecond line\n");
    setup_editor_doc($editor, $filename);

    # Set up file tree with a preview
    require Zepto::FileTree;
    $editor->{file_tree} = Zepto::FileTree->new(root_path => '.');
    $editor->{file_tree}->set_focused(1);

    # Simulate preview state: pretend a file was previewed as a new tab
    my $preview_file = create_temp_file("previewed file content\n");
    $editor->{file_tree}->{pre_preview_tab_index} = $editor->{tab_manager}->active_index();
    # Load the preview file as a new tab (_load_file unfocuses tree, so re-focus after)
    $editor->_load_file($preview_file);
    $editor->{file_tree}->set_focused(1);
    $editor->{file_tree}->{preview_active} = 1;
    $editor->{file_tree}->{preview_path} = $preview_file;

    ok($editor->{file_tree}->{preview_active}, 'Preview is active');
    my $preview_tab_count = $editor->{tab_manager}->tab_count();

    # Click in the document text area — x must be past the tree panel, y=4 for first text row
    my $tree_w = $editor->{file_tree}->panel_width() + 1;
    my $press = {
        type => 'mouse', button => 0, action => 'press',
        x => $tree_w + 10, y => 4, modifiers => [],
    };
    $editor->handle_mouse_event($press);

    # Preview should be confirmed (tab stays), tree unfocused
    ok(!$editor->{file_tree}->focused(), 'Tree unfocused after clicking document area');
    ok(!$editor->{file_tree}->{preview_active}, 'Preview state cleared');
    is($editor->{tab_manager}->tab_count(), $preview_tab_count, 'Preview tab preserved (not dismissed)');
};

# ============================================================================
# Enter key / newline insertion
# ============================================================================

subtest 'Enter key moves cursor to next line in new document' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    # Type some text
    $doc->insert(0, "hello");
    $view->set_cursor(0, 5);

    # Press Enter (via do_enter)
    $editor->do_enter();

    # Cursor should be on line 1, not line 0
    is($view->cursor_line(), 1, 'After Enter, cursor moves to next line');
    is($view->cursor_col(), 0, 'After Enter, cursor at column 0');
    is($doc->line_count(), 2, 'Document now has 2 lines');
};

subtest 'Enter key works with word wrap enabled' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    # Enable word wrap via WrapMap
    $view->set_viewport_size(20, 80);
    my $wm = Zepto::WrapMap->new(document => $doc, width => 80);
    $view->set_wrap_map($wm);

    # Type some text on last (only) line
    $doc->insert(0, "hello world");
    $view->set_cursor(0, 11);

    # Press Enter
    $editor->do_enter();

    # Cursor should be on line 1
    is($view->cursor_line(), 1, 'With word wrap: cursor on next line after Enter');
    is($view->cursor_col(), 0, 'With word wrap: cursor at col 0 after Enter');
};

subtest 'Bracketed paste suppresses auto-indent' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    # Type an indented line
    $doc->insert(0, "    indented");
    $view->set_cursor(0, 12);

    # Normal enter should auto-indent
    $editor->do_enter();
    is($doc->get_line_content(1), '    ', 'Normal Enter auto-indents');

    # Now simulate bracketed paste mode
    $editor->{_bracketed_paste} = 1;
    $view->set_cursor(1, 4);
    $doc->insert($doc->line_col_to_offset(1, 4), "pasted");
    $view->set_cursor(1, 10);
    $editor->do_enter();
    is($doc->get_line_content(2), '', 'Enter during bracketed paste does not auto-indent');
    $editor->{_bracketed_paste} = 0;
};

# ============================================================================
# Key event dispatch: Shift+Alt+Arrow = word select (not column select)
# ============================================================================

subtest 'Shift+Alt+Right selects by word (not column mode)' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("hello world test\n");
    my ($doc, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(0, 0);

    # Send Shift+Alt+Right key event
    my $event = { type => 'key', key => 'right', modifiers => ['shift', 'alt'] };
    $editor->handle_event($event);

    # Should have moved to word boundary AND have selection (not column mode)
    is($view->cursor_col(), 6, 'Cursor moved to next word boundary');
    ok($view->has_selection(), 'Selection is active');
    ok(!$view->column_select(), 'Column mode is NOT active');
};

subtest 'Shift+Alt+Left selects by word backwards' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("hello world test\n");
    my ($doc, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(0, 11);

    # Send Shift+Alt+Left key event
    my $event = { type => 'key', key => 'left', modifiers => ['shift', 'alt'] };
    $editor->handle_event($event);

    # Should have moved back by word AND have selection (not column mode)
    is($view->cursor_col(), 6, 'Cursor moved to prev word boundary');
    ok($view->has_selection(), 'Selection is active');
    ok(!$view->column_select(), 'Column mode is NOT active');
};

subtest 'Column mode toggle then arrows extend column selection' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("hello world\ntest  line\n");
    my ($doc, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(0, 0);

    # Toggle column mode on (⌥C)
    $editor->cmd_toggle_column_mode();
    ok($view->column_select(), 'Column mode active after toggle');

    # Now plain Right arrow should extend column selection
    my $event = { type => 'key', key => 'right', modifiers => [] };
    $editor->handle_event($event);
    is($view->cursor_col(), 1, 'Arrow right moved cursor in column mode');
    ok($view->column_select(), 'Still in column mode');

    # Down arrow should extend column selection vertically
    $event = { type => 'key', key => 'down', modifiers => [] };
    $editor->handle_event($event);
    is($view->cursor_line(), 1, 'Arrow down moved cursor in column mode');
    ok($view->column_select(), 'Still in column mode');

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 0, 'Column rect top');
    is($left, 0, 'Column rect left');
    is($bottom, 1, 'Column rect bottom');
    is($right, 1, 'Column rect right');
};

subtest 'Arrows do NOT enter column mode on their own' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("hello world\ntest  line\n");
    my ($doc, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(0, 0);

    # Plain arrow without column mode toggled — should NOT activate column mode
    my $event = { type => 'key', key => 'right', modifiers => [] };
    $editor->handle_event($event);
    ok(!$view->column_select(), 'Column mode NOT active from plain arrow');

    # Ctrl+Alt+Arrow should also NOT activate column mode (no modifier combos)
    $view->set_cursor(0, 0);
    $event = { type => 'key', key => 'right', modifiers => ['ctrl', 'alt'] };
    $editor->handle_event($event);
    ok(!$view->column_select(), 'Column mode NOT active from Ctrl+Alt+Arrow');
};

subtest 'Column mode: right arrow moves past end of line (virtual space)' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("hi\nworld\n");
    my ($doc, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(0, 0);  # line "hi" (length 2)

    # Toggle column mode
    $editor->cmd_toggle_column_mode();
    ok($view->column_select(), 'Column mode on');

    # Move right 5 times — past end of "hi" (len 2) into virtual space
    for (1..5) {
        my $event = { type => 'key', key => 'right', modifiers => [] };
        $editor->handle_event($event);
    }
    is($view->cursor_col(), 5, 'Cursor at col 5 past EOL in column mode');
    is($view->cursor_line(), 0, 'Still on line 0 (no wrapping)');
};

subtest 'Column mode: left arrow does not wrap to previous line' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("hello\nworld\n");
    my ($doc, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(1, 0);  # start of "world"

    # Toggle column mode
    $editor->cmd_toggle_column_mode();

    # Left arrow at col 0 — should NOT wrap to end of previous line
    my $event = { type => 'key', key => 'left', modifiers => [] };
    $editor->handle_event($event);
    is($view->cursor_line(), 1, 'Still on line 1 (no wrapping)');
    is($view->cursor_col(), 0, 'Still at col 0');
};

subtest 'Normal mode: right arrow still wraps at EOL' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("hi\nworld\n");
    my ($doc, $view) = setup_editor_doc($editor, $filename);
    $view->set_cursor(0, 2);  # end of "hi"

    # Not in column mode — right should wrap to next line
    ok(!$view->column_select(), 'Not in column mode');
    $view->move_right(0);
    is($view->cursor_line(), 1, 'Wrapped to next line');
    is($view->cursor_col(), 0, 'At col 0 of next line');
};

# =============================================================================
# Recent files tracking
# =============================================================================

subtest 'Recent files - tracking and ordering' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => mock_terminal(),
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );
    # Initialize with empty state
    $editor->{_recent_files} = [];

    # Track some files (use non-temp absolute paths)
    $editor->_track_recent_file('/home/user/a.txt');
    $editor->_track_recent_file('/home/user/b.txt');
    $editor->_track_recent_file('/home/user/c.txt');

    is(scalar @{$editor->{_recent_files}}, 3, 'Three files tracked');
    is($editor->{_recent_files}[0], '/home/user/c.txt', 'Most recent is first');
    is($editor->{_recent_files}[1], '/home/user/b.txt', 'Second most recent');
    is($editor->{_recent_files}[2], '/home/user/a.txt', 'Oldest is last');

    # Re-open a.txt — should move to front
    $editor->_track_recent_file('/home/user/a.txt');
    is(scalar @{$editor->{_recent_files}}, 3, 'Still three files (no duplicate)');
    is($editor->{_recent_files}[0], '/home/user/a.txt', 'Re-opened file moved to front');
    is($editor->{_recent_files}[1], '/home/user/c.txt', 'Previous first is now second');
};

subtest 'Recent files - max limit' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => mock_terminal(),
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );
    $editor->{_recent_files} = [];

    # Track more than the max
    for my $i (1 .. 60) {
        $editor->_track_recent_file("/home/user/file_$i.txt");
    }

    ok(scalar @{$editor->{_recent_files}} <= Zepto::Editor::RECENT_FILES_MAX,
       'Recent files list respects max limit');
    is($editor->{_recent_files}[0], '/home/user/file_60.txt', 'Most recent is first');
};

subtest 'Recent files - temp files filtered' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $editor = Zepto::Editor->new(
        terminal => mock_terminal(),
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );
    $editor->{_recent_files} = [];

    # Track a real file
    $editor->_track_recent_file('/home/user/real.txt');

    # Track temp files — should be ignored
    $editor->_track_recent_file('/tmp/test_file.txt');
    $editor->_track_recent_file('/private/tmp/scratch.txt');
    $editor->_track_recent_file('/var/folders/xx/yy/T/tmp.12345');

    is(scalar @{$editor->{_recent_files}}, 1, 'Only non-temp file tracked');
    is($editor->{_recent_files}[0], '/home/user/real.txt', 'Real file preserved');
};

subtest 'Recent files - palette items' => sub {
    my $cmd = Zepto::CommandRegistry->find_command('recent_files');
    ok(defined $cmd, 'Recent Files command exists in registry');
    is($cmd->{shortcut}, "\x{2303}E", 'Shortcut is ⌃E');
    is($cmd->{section}, 'FILE', 'In FILE section');
    is($cmd->{method}, 'cmd_recent_files', 'Correct method');
};

# ============================================================================
# Session Restore Tests (bugs.md P2 "Session restore")
# ============================================================================

subtest 'Session restore - save and restore round trip' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);

    my $file_a = create_temp_file("aaa\nbbb\nccc\nddd\neee\n");
    my $file_b = create_temp_file("111\n222\n333\n");

    my $editor1 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    my (undef, $view_a) = setup_editor_doc($editor1, $file_a);
    my (undef, $view_b) = setup_editor_doc($editor1, $file_b);
    $view_a->set_cursor(2, 1);
    $view_a->{scroll_line} = 1;
    $view_b->set_cursor(1, 2);
    $editor1->{tab_manager}->set_active(0);  # a is the active tab

    $editor1->_save_session();

    my $editor2 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    my $restored = $editor2->_restore_session();
    ok($restored, 'Session restored');
    is($editor2->{tab_manager}->tab_count(), 2, 'Two tabs restored');
    is($editor2->{tab_manager}->active_index(), 0, 'Active tab restored (a)');

    my $tab0 = $editor2->{tab_manager}->tab_at(0);
    is($tab0->{file_path}, File::Spec->rel2abs($file_a), 'First tab is file_a');
    is($tab0->{view}->cursor_line(), 2, 'Cursor line restored');
    is($tab0->{view}->cursor_col(), 1, 'Cursor col restored');
    is($tab0->{view}->scroll_line(), 1, 'Scroll line restored');

    my $tab1 = $editor2->{tab_manager}->tab_at(1);
    is($tab1->{file_path}, File::Spec->rel2abs($file_b), 'Second tab is file_b');
    is($tab1->{view}->cursor_line(), 1, 'Second tab cursor line restored');
    is($tab1->{view}->cursor_col(), 2, 'Second tab cursor col restored');
};

subtest 'Session restore - no saved session returns false' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $editor = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);

    is($editor->_restore_session(), 0, 'Nothing to restore returns false');
    is($editor->{tab_manager}->tab_count(), 0, 'No tabs added');
};

subtest 'Session restore - missing files are skipped individually' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);

    my $file_a = create_temp_file("keep me\n");
    my $to_delete = create_temp_file("will vanish before restore\n");

    my $editor1 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    setup_editor_doc($editor1, $to_delete); # tab 0: exists now, gone before restore
    setup_editor_doc($editor1, $file_a);    # tab 1: still exists
    $editor1->{tab_manager}->set_active(1); # active is file_a

    $editor1->_save_session();

    # Now delete the file for tab 0 — it should be skipped at restore time.
    unlink $to_delete or die "unlink $to_delete: $!";

    my $editor2 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    my $restored = $editor2->_restore_session();
    ok($restored, 'Restore succeeds despite one missing file');
    is($editor2->{tab_manager}->tab_count(), 1, 'Only the existing file was restored');
    is($editor2->{tab_manager}->tab_at(0)->{file_path}, File::Spec->rel2abs($file_a),
       'Surviving tab is file_a');
    is($editor2->{tab_manager}->active_index(), 0, 'Active index remapped after skip');
};

subtest 'Session restore - untitled tabs are not saved' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);

    my $editor = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    my $doc = Zepto::Document->new();
    my $view = Zepto::View->new(document => $doc);
    my $find_engine = Zepto::FindEngine->new(document => $doc);
    my $highlighter = Zepto::Highlighter->new();
    $editor->{tab_manager}->add_tab(
        document => $doc, view => $view, find_engine => $find_engine,
        highlighter => $highlighter, untitled_name => '[untitled]',
        # no file_path — unsaved buffer
    );

    $editor->_save_session();

    my $history = $store->get('history');
    ok(!$history->{sessions} || !%{$history->{sessions}},
       'Untitled-only session is not persisted');
};

subtest 'Session restore - gated by restore_session preference' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $file_a = create_temp_file("pref gate\n");

    my $editor1 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    setup_editor_doc($editor1, $file_a);
    $editor1->{prefs}->set_restore_session(0);
    $editor1->_save_session();

    my $history = $store->get('history');
    ok(!$history->{sessions} || !%{$history->{sessions}},
       'Nothing saved while preference is off');

    # Turn it back on and save for real, then confirm a second editor with
    # the preference off can't load it even though it's on disk.
    $editor1->{prefs}->set_restore_session(1);
    $editor1->_save_session();

    my $editor2 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    $editor2->{prefs}->set_restore_session(0);
    is($editor2->_restore_session(), 0, 'Restore is a no-op while preference is off');
};

subtest 'Session restore - not eligible on explicit-file / dir-focus launches' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $file_a = create_temp_file("eligibility\n");

    # Seed a real saved session first (bare-launch equivalent).
    my $editor1 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    setup_editor_doc($editor1, $file_a);
    $editor1->_save_session();

    my $history = $store->get('history');
    ok($history->{sessions} && %{$history->{sessions}}, 'Session seeded');

    # A run that isn't session-eligible (e.g. launched with an explicit
    # file, or `zepto .`) must not touch — and in particular must not
    # clear — the saved session, even if its own tabs are untitled.
    my $editor2 = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    $editor2->{_session_eligible} = 0;
    my $doc = Zepto::Document->new();
    my $view = Zepto::View->new(document => $doc);
    $editor2->{tab_manager}->add_tab(
        document => $doc, view => $view,
        find_engine => Zepto::FindEngine->new(document => $doc),
        highlighter => Zepto::Highlighter->new(),
    );
    $editor2->_save_session();

    my $history_after = $store->get('history');
    ok($history_after->{sessions} && %{$history_after->{sessions}},
       'Ineligible run does not clear the saved session');
};

# ============================================================================
# Toggle Comment Tests
# ============================================================================

subtest 'Location history: go back/forward' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line one\nline two\nline three\nline four\nline five\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    # Start at line 0
    my $view = $editor->active_view();
    is($view->cursor_line(), 0, 'Start at line 0');

    # Record location and jump to line 3
    $editor->_record_location();
    $view->set_cursor(3, 0, 0);
    is($view->cursor_line(), 3, 'Jumped to line 3');

    # Record location and jump to line 1
    $editor->_record_location();
    $view->set_cursor(1, 0, 0);
    is($view->cursor_line(), 1, 'Jumped to line 1');

    # Go back — should return to line 3
    $editor->cmd_go_back();
    is($view->cursor_line(), 3, 'Go back returns to line 3');

    # Go back again — should return to line 0
    $editor->cmd_go_back();
    is($view->cursor_line(), 0, 'Go back again returns to line 0');

    # Go forward — should return to line 3
    $editor->cmd_go_forward();
    is($view->cursor_line(), 3, 'Go forward returns to line 3');

    # Go forward — should return to line 1
    $editor->cmd_go_forward();
    is($view->cursor_line(), 1, 'Go forward returns to line 1');

    # No more forward entries
    $editor->cmd_go_forward();
    is($view->cursor_line(), 1, 'No more forward — stays at line 1');
};

subtest 'Toggle comment: line prefix comments (Perl)' => sub {
    my $term = mock_terminal();
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.pl');
    print $fh "my \$x = 1;\nmy \$y = 2;\n";
    close $fh;
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);
    # Trigger highlighter to detect language
    $editor->active_highlighter()->set_file($filename);

    # Comment single line
    $editor->active_view()->set_cursor(0, 0, 0);
    $editor->cmd_toggle_comment();
    is($editor->active_doc()->get_line_content(0), '# my $x = 1;', 'Perl line commented with #');

    # Uncomment
    $editor->cmd_toggle_comment();
    is($editor->active_doc()->get_line_content(0), 'my $x = 1;', 'Perl line uncommented');
};

subtest 'Toggle comment: HTML block comments' => sub {
    my $term = mock_terminal();
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.html');
    print $fh "<div>hello</div>\n<p>world</p>\n";
    close $fh;
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);
    $editor->active_highlighter()->set_file($filename);

    # Comment HTML line — should use <!-- -->
    $editor->active_view()->set_cursor(0, 0, 0);
    $editor->cmd_toggle_comment();
    is($editor->active_doc()->get_line_content(0), '<!-- <div>hello</div> -->', 'HTML commented with <!-- -->');

    # Uncomment
    $editor->cmd_toggle_comment();
    is($editor->active_doc()->get_line_content(0), '<div>hello</div>', 'HTML uncommented');
};

subtest 'Toggle comment: CSS block comments' => sub {
    my $term = mock_terminal();
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.css');
    print $fh "body { color: red; }\n";
    close $fh;
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);
    $editor->active_highlighter()->set_file($filename);

    # Comment CSS line — should use /* */
    $editor->active_view()->set_cursor(0, 0, 0);
    $editor->cmd_toggle_comment();
    is($editor->active_doc()->get_line_content(0), '/* body { color: red; } */', 'CSS commented with /* */');

    # Uncomment
    $editor->cmd_toggle_comment();
    is($editor->active_doc()->get_line_content(0), 'body { color: red; }', 'CSS uncommented');
};

subtest 'Toggle comment: HTML context-aware (script block uses //)' => sub {
    my $term = mock_terminal();
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.html');
    print $fh "<html>\n<script>\nvar x = 1;\n</script>\n</html>\n";
    close $fh;
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);
    $editor->active_highlighter()->set_file($filename);

    # Force tokenize lines 0-2 to build up line states
    my $doc = $editor->active_doc();
    my $hl = $editor->active_highlighter();
    for my $i (0..2) {
        $hl->tokenize_line($doc->get_line_content($i), $i);
    }

    # Line 2 ("var x = 1;") is inside <script> — should use // comments
    $editor->active_view()->set_cursor(2, 0, 0);
    $editor->cmd_toggle_comment();
    is($doc->get_line_content(2), '// var x = 1;', 'JS inside HTML commented with //');

    # Uncomment
    $editor->cmd_toggle_comment();
    is($doc->get_line_content(2), 'var x = 1;', 'JS inside HTML uncommented');
};

# ============================================================================
# Performance Profiling
# ============================================================================

subtest '_record_frame populates perf log' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("line 1\nline 2\n");
    setup_editor_doc($editor, $filename);

    is(scalar @{$editor->{_perf_log}}, 0, 'Perf log starts empty');

    # Record a frame
    $editor->_record_frame(time(), 50.0, 10.0, 40.0, 'a');
    is(scalar @{$editor->{_perf_log}}, 1, 'One entry after recording');
    is($editor->{_perf_log}[0]{event_type}, 'char', 'Char input classified');

    # Record more frames
    $editor->_record_frame(time(), 30.0, 5.0, 25.0, "\x03");
    is(scalar @{$editor->{_perf_log}}, 2, 'Two entries');
    is($editor->{_perf_log}[1]{event_type}, 'ctrl', 'Ctrl input classified');

    # Slowest should be first (sorted descending)
    ok($editor->{_perf_log}[0]{total_ms} >= $editor->{_perf_log}[1]{total_ms},
       'Sorted descending by total_ms');
};

subtest '_record_frame caps at 20 and keeps slowest' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("test\n");
    setup_editor_doc($editor, $filename);

    # Fill with 20 entries of increasing time
    for my $i (1..20) {
        $editor->_record_frame(time(), $i * 1.0, 0.5, $i * 1.0 - 0.5, 'x');
    }
    is(scalar @{$editor->{_perf_log}}, 20, 'Capped at 20');

    # Smallest entry should be 1.0ms
    my $min = $editor->{_perf_log}[-1]{total_ms};
    ok($min <= 1.0 + 0.001, "Smallest is ~1.0ms (got $min)");

    # Add a frame slower than the fastest (which is 1.0ms) but not slower than 20.0ms
    $editor->_record_frame(time(), 1.5, 0.5, 1.0, 'y');
    is(scalar @{$editor->{_perf_log}}, 20, 'Still capped at 20');
    my $new_min = $editor->{_perf_log}[-1]{total_ms};
    ok($new_min >= 1.5 - 0.001, "New smallest is >= 1.5ms (got $new_min) — replaced the 1.0ms entry");

    # Add a frame slower than everything
    $editor->_record_frame(time(), 999.0, 1.0, 998.0, 'z');
    is($editor->{_perf_log}[0]{total_ms}, 999.0, 'Slowest frame is at position 0');

    # Add a frame faster than the current minimum — should be ignored
    my $current_min = $editor->{_perf_log}[-1]{total_ms};
    $editor->_record_frame(time(), 0.1, 0.05, 0.05, 'a');
    is($editor->{_perf_log}[-1]{total_ms}, $current_min, 'Faster-than-min frame is discarded');
};

subtest '_record_frame classifies event types' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("test\n");
    setup_editor_doc($editor, $filename);

    # Timeout (empty input)
    $editor->_record_frame(time(), 10.0, 5.0, 5.0, '');
    is($editor->{_perf_log}[-1]{event_type}, 'timeout', 'Empty input = timeout');

    # Char
    $editor->_record_frame(time(), 11.0, 5.0, 6.0, 'h');
    is($editor->{_perf_log}[0]{event_type}, 'char', 'Regular char');

    # Ctrl
    $editor->{_perf_log} = [];
    $editor->_record_frame(time(), 10.0, 5.0, 5.0, "\x01");
    is($editor->{_perf_log}[0]{event_type}, 'ctrl', 'Ctrl char');

    # Escape alone
    $editor->{_perf_log} = [];
    $editor->_record_frame(time(), 10.0, 5.0, 5.0, "\x1b");
    is($editor->{_perf_log}[0]{event_type}, 'escape', 'Escape alone');

    # Alt (escape + more)
    $editor->{_perf_log} = [];
    $editor->_record_frame(time(), 10.0, 5.0, 5.0, "\x1bx");
    is($editor->{_perf_log}[0]{event_type}, 'alt', 'Alt combo');
};

subtest 'cmd_show_perf_log with no frames' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("test\n");
    setup_editor_doc($editor, $filename);

    $editor->cmd_show_perf_log();

    # Should have opened a new tab
    is($editor->{tab_manager}->tab_count(), 2, 'New tab opened');
    my $doc = $editor->active_doc();
    like($doc->get_line_content(0), qr/No frames recorded yet/, 'Empty state message');
};

subtest 'cmd_show_perf_log with frames' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $filename = create_temp_file("test\n");
    setup_editor_doc($editor, $filename);

    # Record a couple of frames
    $editor->{_perf} = { vcs_diff => 1 };
    $editor->_record_frame(time(), 72.3, 5.1, 67.2, 'a');
    $editor->{_perf} = {};
    $editor->_record_frame(time(), 55.0, 2.0, 53.0, 'b');

    $editor->cmd_show_perf_log();

    my $doc = $editor->active_doc();
    like($doc->get_line_content(0), qr/Zepto Performance Report/, 'Report header');
    like($doc->get_line_content(3), qr/Showing: 2 slowest frames/, 'Frame count');

    # Check that the tab is named "Performance Log"
    my $tab = $editor->active_tab();
    is($tab->{untitled_name}, 'Performance Log', 'Tab named correctly');
};

# ============================================================================
# Incremental WrapMap update on single-char edits
# ============================================================================
subtest 'do_insert_char uses incremental wrap update' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("hello world\nsecond line\n");
    my $editor = Zepto::Editor->new(terminal => $term);
    my ($doc, $view) = setup_editor_doc($editor, $filename);

    # Enable word wrap by setting up a WrapMap
    my $wm = Zepto::WrapMap->new(document => $doc, width => 80);
    $view->set_wrap_map($wm);

    # Force initial build
    $wm->total_visual_rows();
    ok(!$wm->{_dirty}, 'WrapMap is clean after initial build');
    my $initial_version = $wm->{_last_content_version};

    # Insert a character
    $editor->do_insert_char('X');

    # The WrapMap should NOT be dirty — invalidate_line synced the version
    ok(!$wm->{_dirty}, 'WrapMap not dirty after single-char insert (incremental path)');
    is($wm->{_last_content_version}, $doc->content_version(),
       'WrapMap version synced with document after insert');
};

subtest 'do_backspace within line uses incremental wrap' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("hello world\nsecond line\n");
    my $editor = Zepto::Editor->new(terminal => $term);
    my ($doc, $view) = setup_editor_doc($editor, $filename);

    # Move cursor to middle of line 0
    $view->set_cursor(0, 5);

    my $wm = Zepto::WrapMap->new(document => $doc, width => 80);
    $view->set_wrap_map($wm);
    $wm->total_visual_rows();

    $editor->do_backspace();

    ok(!$wm->{_dirty}, 'WrapMap not dirty after within-line backspace');
    is($wm->{_last_content_version}, $doc->content_version(),
       'Version synced after backspace');
};

subtest 'do_backspace at line start triggers full rebuild' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("hello\nworld\n");
    my $editor = Zepto::Editor->new(terminal => $term);
    my ($doc, $view) = setup_editor_doc($editor, $filename);

    # Move cursor to start of line 1 (backspace will join lines)
    $view->set_cursor(1, 0);

    my $wm = Zepto::WrapMap->new(document => $doc, width => 80);
    $view->set_wrap_map($wm);
    $wm->total_visual_rows();

    $editor->do_backspace();

    # Should have called invalidate_wrap_map() → _dirty = 1
    ok($wm->{_dirty}, 'WrapMap dirty after line-joining backspace (full rebuild needed)');
};

subtest 'do_delete within line uses incremental wrap' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("hello world\nsecond line\n");
    my $editor = Zepto::Editor->new(terminal => $term);
    my ($doc, $view) = setup_editor_doc($editor, $filename);

    $view->set_cursor(0, 3);

    my $wm = Zepto::WrapMap->new(document => $doc, width => 80);
    $view->set_wrap_map($wm);
    $wm->total_visual_rows();

    $editor->do_delete();

    ok(!$wm->{_dirty}, 'WrapMap not dirty after within-line delete');
    is($wm->{_last_content_version}, $doc->content_version(),
       'Version synced after delete');
};

# ============================================================================
# File tree reveals opened file
# ============================================================================

subtest '_load_file updates file tree to reveal new file' => sub {
    my $term = mock_terminal();
    my $dir = Cwd::realpath(tempdir(CLEANUP => 1));

    # Create nested file structure
    mkdir "$dir/sub";
    my $file1 = "$dir/first.txt";
    my $file2 = "$dir/sub/second.txt";
    open my $fh1, '>', $file1; print $fh1 "aaa\n"; close $fh1;
    open my $fh2, '>', $file2; print $fh2 "bbb\n"; close $fh2;

    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();

    # Set up a file tree rooted at the temp dir
    require Zepto::FileTree;
    $editor->{file_tree} = Zepto::FileTree->new(root_path => $dir);

    # Open a file — tree should update to show it
    $editor->_load_file($file2);

    # Resolve to match what FileTree stores (relative path)
    my $rel = File::Spec->abs2rel($file2, $dir);
    is($editor->{file_tree}->{current_file}, $rel,
       'File tree current_file updated after _load_file');
};

subtest '_jump_to_location switches to existing tab and updates tree' => sub {
    my $term = mock_terminal();
    my $dir = Cwd::realpath(tempdir(CLEANUP => 1));

    my $file1 = "$dir/a.txt";
    my $file2 = "$dir/b.txt";
    open my $fh1, '>', $file1; print $fh1 "aaa\n"; close $fh1;
    open my $fh2, '>', $file2; print $fh2 "bbb\nline2\nline3\n"; close $fh2;

    my $editor = Zepto::Editor->new(terminal => $term);

    # Set up file tree
    require Zepto::FileTree;
    $editor->{file_tree} = Zepto::FileTree->new(root_path => $dir);

    # Open two files in tabs
    $editor->_load_file($file1);
    $editor->_load_file($file2);
    is($editor->active_file_path(), $file2, 'Active tab is file2');

    # Jump back to file1 via _jump_to_location (simulates find-in-files)
    $editor->_jump_to_location({ file => $file1, line => 0, col => 0 });
    is($editor->active_file_path(), $file1,
       '_jump_to_location switched to correct tab');

    my $rel = File::Spec->abs2rel($file1, $dir);
    is($editor->{file_tree}->{current_file}, $rel,
       'File tree updated after _jump_to_location');
};

subtest 'Save As activates syntax highlighting for new filename' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();

    # New file has no highlighter grammar
    my $hl = $editor->active_highlighter();
    ok(!$hl->{grammar}, 'New untitled file has no grammar');

    # Simulate Save As: set path, save, update tab, call set_file
    my $tmpfile = create_temp_file('');
    my $py_file = $tmpfile . '.py';
    rename $tmpfile, $py_file;

    my $doc = $editor->active_doc();
    $doc->set_path($py_file);
    eval { $doc->save(); };
    my $tab = $editor->active_tab();
    $tab->{file_path} = $py_file;
    $tab->{untitled_name} = undef;
    $hl->set_file($py_file);

    ok($hl->{grammar}, 'Grammar activated after set_file with .py extension');
    like($hl->{grammar_class}, qr/Python/, 'Python grammar detected for .py file');

    unlink $py_file;
};

# ============================================================================
# cmd_save_as (bugs.md P3 "No Save As command in palette")
# ============================================================================
subtest 'cmd_save_as opens footer input prefilled with current path' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_save_as();

    is($editor->{state}, 'footer_input', 'cmd_save_as opens footer input');
    is($editor->{footer_input}{prompt}, 'Save As:', 'Prompt is "Save As:"');
    is($editor->{footer_input}{widget}->value(), $filename,
       'Prefilled with the document\'s current path');
};

subtest 'cmd_save_as writes the file, updates the tab, and activates syntax highlighting' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("def foo():\n    return 1\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    my $hl = $editor->active_highlighter();
    ok(!$hl->{grammar}, 'Plain temp file has no grammar before Save As');

    $editor->cmd_save_as();
    is($editor->{state}, 'footer_input', 'Footer input open');

    my $py_file = $filename . '.py';
    # Replace the pre-selected prefilled value with the new path
    $editor->handle_input($py_file);
    $editor->handle_input("\r");

    is($editor->{state}, 'editing', 'Back to editing after submit');
    ok(-e $py_file, 'New file exists on disk');

    my $tab = $editor->active_tab();
    is($tab->{file_path}, $py_file, 'Tab file_path updated to the new path');
    is($tab->{untitled_name}, undef, 'Tab untitled_name cleared');

    ok($hl->{grammar}, 'Grammar activated for the new .py extension');
    like($hl->{grammar_class}, qr/Python/, 'Python grammar detected');

    unlink $py_file;
};

subtest 'cmd_save_as prompts before overwriting a different existing file' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("current content\n");
    my $other = create_temp_file("other content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_save_as();
    $editor->handle_input($other);
    $editor->handle_input("\r");

    is($editor->{state}, 'prompt', 'Overwrite confirmation prompt opens');
    like($editor->{prompt}{text}, qr/already exists/, 'Prompt warns the file already exists');

    # Decline: file on disk must be untouched
    $editor->handle_input('n');
    is($editor->{state}, 'editing', 'Back to editing after declining');

    open(my $fh, '<', $other) or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    is($content, "other content\n", 'Declining overwrite leaves the other file untouched');

    unlink $filename, $other;
};

subtest 'cmd_save_as overwrites when confirmed' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("current content\n");
    my $other = create_temp_file("other content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_save_as();
    $editor->handle_input($other);
    $editor->handle_input("\r");
    is($editor->{state}, 'prompt', 'Overwrite confirmation prompt opens');

    $editor->handle_input('y');
    is($editor->{state}, 'editing', 'Back to editing after confirming');

    open(my $fh, '<', $other) or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    is($content, "current content\n", 'Confirming overwrite writes this document\'s content');

    my $tab = $editor->active_tab();
    is($tab->{file_path}, $other, 'Tab now points at the overwritten file');

    unlink $filename, $other;
};

subtest 'cmd_save_as does not prompt when re-saving to the document\'s own path' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);

    $editor->cmd_save_as();
    # Submit without changing the prefilled (== current) path
    $editor->handle_input($filename);
    $editor->handle_input("\r");

    is($editor->{state}, 'editing', 'No overwrite prompt — straight back to editing');

    unlink $filename;
};

# ============================================================================
# Render decision after input batches (QA-REG-101)
# ============================================================================
# Regression: after a mouse hover-motion event, the main loop skipped
# rendering for ALL subsequent keyboard input — typed text and cursor moves
# were applied to the document but never drawn until the next click/scroll.
# The render decision must be per-batch: skip only when the batch contained
# nothing but hover motion that changed no hover target.
subtest 'Typing after hover motion still renders' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("alpha\nbeta\n");
    my $editor = Zepto::Editor->new(terminal => $term);
    setup_editor_doc($editor, $filename);

    # Idle hover motion over the text area (no target change): no render needed
    $editor->handle_input("\x1b[<35;10;3M");
    ok(!$editor->_input_needs_render(),
       'Idle hover motion alone does not require a render');

    # A keypress in a LATER batch must render, even though the previous
    # batch ended on a hover motion (the original bug: flag persisted)
    $editor->handle_input("\x1b[B");
    ok($editor->_input_needs_render(),
       'Arrow key after an earlier hover motion requires a render');

    # A batch that mixes hover motion and typing must render, even when
    # the hover motion is the LAST event in the batch
    $editor->handle_input("Z" . "\x1b[<35;12;3M");
    ok($editor->_input_needs_render(),
       'Batch with typing followed by hover motion requires a render');
    like($editor->active_doc()->get_line(1), qr/Z/,
         'Typed char was applied to the document');
};

# ============================================================================
# QA-REG-154: File-tree preview failure must surface an error message
# ============================================================================

subtest 'Tree preview of unreadable file surfaces an error message' => sub {
    plan skip_all => 'chmod permission test not meaningful as root' if $> == 0;

    # _tree_preview_current() passes the tree node's path (relative to the
    # tree root) straight into _create_document_state(), which resolves it
    # against the process cwd (not the tree's root_path) — so the test has
    # to actually chdir into the tree root, same as the real editor does
    # when it opens a directory. Restore cwd unconditionally afterward.
    my $orig_cwd = Cwd::getcwd();
    my $dir = Cwd::realpath(tempdir(CLEANUP => 1));
    my $bad_path = "$dir/secret.txt";

    my $ok = eval {
        open(my $fh, '>', $bad_path) or die $!;
        print $fh "top secret\n";
        close $fh;

        chdir $dir or die "chdir failed: $!";

        my $term = mock_terminal();
        my $editor = Zepto::Editor->new(terminal => $term);

        # Give the editor an initial tab so it has somewhere to return to
        my $initial = create_temp_file("hello\n");
        setup_editor_doc($editor, $initial);

        # Build the tree with the file readable at scan time.
        # NOTE (behavioral discovery): FileTree::_scan_dir_one_level only
        # lists files that pass `-r` at scan time, so a chmod-000 file
        # never appears in the tree in the first place — you can't
        # navigate to it to trigger a preview. The realistic way this bug
        # fires is a TOCTOU race: the file was readable when the tree was
        # scanned but becomes unreadable (permissions revoked, unmounted,
        # etc.) by the time the user arrows onto it and a preview is
        # attempted. We simulate that race here.
        require Zepto::FileTree;
        $editor->{file_tree} = Zepto::FileTree->new(root_path => $dir);
        $editor->{file_tree}->set_focused(1);

        # Point the tree cursor at the file's node (scanned while readable)
        my $flat = $editor->{file_tree}->{flat_list};
        my ($idx) = grep { $flat->[$_]{path} eq 'secret.txt' } 0 .. $#$flat;
        ok(defined $idx, 'File appears in the tree listing while readable');
        $editor->{file_tree}->{cursor} = $idx;

        # Now revoke read permission — simulating the race — right before preview.
        chmod 0000, $bad_path or die "chmod failed: $!";

        # Sanity check: previewing should actually fail (permission denied)
        # in this test environment, otherwise this test proves nothing.
        my $probe = eval { Zepto::Document->load($bad_path) };
        ok(!$probe, 'Sanity check: loading the now-unreadable file dies as expected')
            or diag("Test environment can read chmod 0000 files (e.g. running as "
                  . "root) — this test cannot exercise the failure path here.");

        $editor->{message} = '';
        $editor->{message_is_error} = 0;

        $editor->_tree_preview_current();

        ok($editor->{message_is_error}, 'An error message is surfaced for the failed preview')
            or diag("message=" . ($editor->{message} // '(undef)'));
        like($editor->{message}, qr/preview/i, 'Error message mentions the preview failure')
            if $editor->{message};

        1;
    };
    my $err = $@;

    chmod 0644, $bad_path;  # restore so tempdir cleanup can remove it
    chdir $orig_cwd or die "failed to restore cwd: $!";

    ok($ok, 'Test body completed without dying') or diag("error: $err");
};

# ============================================================================
# StateStore test isolation (bugs.md P1: "Zepto::Editor->new() defaults to
# the developer's real ~/.config/zepto StateStore")
# ============================================================================
subtest 'Editor->new() with no state_store never touches the real config dir under the test harness' => sub {
    # Sanity check the whole guard rests on: Test::Harness/prove sets this
    # env var automatically. If it's not set here, the rest of this subtest
    # would prove nothing (the harness-only redirect wouldn't engage).
    ok($ENV{HARNESS_ACTIVE}, 'Sanity: HARNESS_ACTIVE is set while running under prove');

    my $real_home = $ENV{HOME} || (getpwuid($<))[7] || '.';
    my $real_xdg  = $ENV{XDG_CONFIG_HOME} || "$real_home/.config";
    my $real_default_base_dir = "$real_xdg/zepto";
    my $real_prefs_file = File::Spec->catfile($real_default_base_dir, 'preferences.json');
    my $mtime_before = -e $real_prefs_file ? (stat($real_prefs_file))[9] : undef;

    # Two independent Editor instances, neither given a state_store — this is
    # exactly the pattern used by 100+ call sites in this file.
    my $editor_a = Zepto::Editor->new(terminal => mock_terminal());
    my $editor_b = Zepto::Editor->new(terminal => mock_terminal());

    my $base_a = $editor_a->{state_store}->base_dir();
    my $base_b = $editor_b->{state_store}->base_dir();

    isnt($base_a, $real_default_base_dir,
        'Resolved base_dir is not the real $XDG_CONFIG_HOME/zepto or ~/.config/zepto');
    unlike($base_a, qr{^\Q$real_home\E(/|$)},
        "Resolved base_dir is not anywhere under the real HOME ($real_home)");
    isnt($base_a, $base_b,
        'Two separate Editor->new() calls get separate per-call temp dirs (no cross-test sharing)');

    # Actually flip a preference through the editor (the exact action that
    # corrupted the real machine's preferences.json in the incident this
    # guards against) and confirm the real file was never touched.
    $editor_a->{prefs}->set_soft_tabs(0);

    ok(-e File::Spec->catfile($base_a, 'preferences.json'),
        'The preference write did land somewhere — in the isolated temp base_dir');

    my $mtime_after = -e $real_prefs_file ? (stat($real_prefs_file))[9] : undef;
    is($mtime_after, $mtime_before,
        "Real $real_prefs_file was not created or modified by this test");
};

# ============================================================================
# cmd_close_tab (bugs.md Scorecard round 3: "19 of 56 cmd_* command-dispatch
# wrappers have zero test coverage, including one with data-loss-adjacent
# logic" — cmd_close_tab is the highest-value target: "Save if dirty, then
# close... Only close if save succeeded".)
# ============================================================================
subtest 'cmd_close_tab: closing a clean tab just closes it, no save' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $file_a = create_temp_file("file a\n");
    my $file_b = create_temp_file("file b\n");

    my $editor = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    setup_editor_doc($editor, $file_a);
    setup_editor_doc($editor, $file_b);  # becomes active (index 1)

    is($editor->{tab_manager}->tab_count(), 2, 'Two tabs open');
    is($editor->{tab_manager}->active_index(), 1, 'File B tab is active');
    ok(!$editor->active_doc()->is_dirty(), 'Active document (B) is clean');

    my $mtime_before = (stat($file_b))[9];
    $editor->{message} = '';
    $editor->{message_is_error} = 0;

    $editor->cmd_close_tab();

    is($editor->{tab_manager}->tab_count(), 1, 'Tab B was closed');
    is($editor->{state}, 'editing', 'Editor stays in editing state (not quit)');
    is($editor->{tab_manager}->active_index(), 0, 'File A tab is now active');
    is($editor->active_file_path(), File::Spec->rel2abs($file_a),
        'Remaining active tab is file A');
    is((stat($file_b))[9], $mtime_before, 'File B was never written (no save happened)');
    unlike($editor->{message} // '', qr/^Saved:/, 'No "Saved" message was shown for a clean close');
};

subtest 'cmd_close_tab: closing a dirty tab saves first, then closes, when save succeeds' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $file_a = create_temp_file("file a\n");
    my $file_b = create_temp_file("original b\n");

    my $editor = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    setup_editor_doc($editor, $file_a);
    setup_editor_doc($editor, $file_b);  # becomes active (index 1)

    $editor->active_doc()->insert(0, "edited ");
    ok($editor->active_doc()->is_dirty(), 'Active document (B) is dirty before close');

    $editor->cmd_close_tab();

    is($editor->{tab_manager}->tab_count(), 1, 'Tab B was closed after successful save');
    is($editor->{tab_manager}->active_index(), 0, 'File A tab is now active');

    open(my $fh, '<', $file_b) or die "can't read $file_b: $!";
    local $/;
    my $on_disk = <$fh>;
    close $fh;
    like($on_disk, qr/^edited original b/, 'File B on disk reflects the edit made before close');
};

subtest 'cmd_close_tab: closing a dirty tab does NOT close when save FAILS (data-loss prevention)' => sub {
    my $orig_cwd = Cwd::getcwd();
    my $tmpdir = tempdir(CLEANUP => 1);
    my $locked_dir = "$tmpdir/locked";
    mkdir $locked_dir or die "mkdir failed: $!";
    my $locked_file = "$locked_dir/b.txt";
    open(my $fh, '>', $locked_file) or die "can't create $locked_file: $!";
    print $fh "original locked\n";
    close $fh;

    my $file_a = create_temp_file("file a\n");

    my $ok = eval {
        my $store = Zepto::StateStore->new(base_dir => "$tmpdir/state");
        my $editor = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
        setup_editor_doc($editor, $file_a);
        setup_editor_doc($editor, $locked_file);  # becomes active (index 1)

        # Document::save() writes its atomic temp file via File::Temp::tempfile
        # with DIR => dirname($path) — so it's the *directory's* write
        # permission that gates save, not the target file's own mode.
        # Revoke write permission on the directory to force save() to die.
        chmod 0500, $locked_dir or die "chmod failed: $!";

        # Sanity check: confirm the environment actually enforces this,
        # otherwise (e.g. running as root) this test proves nothing.
        my $probe_ok = eval {
            open(my $pfh, '>', "$locked_dir/probe.txt") or die $!;
            close $pfh;
            unlink "$locked_dir/probe.txt";
            1;
        };
        ok(!$probe_ok, 'Sanity check: locked directory actually rejects writes in this test environment')
            or diag("Test environment can write to a chmod 0500 directory (e.g. running as "
                  . "root) — this test cannot exercise the failure path here.");

        $editor->active_doc()->insert(0, "edited ");
        ok($editor->active_doc()->is_dirty(), 'Active document (locked b) is dirty before close');

        $editor->{message} = '';
        $editor->{message_is_error} = 0;

        $editor->cmd_close_tab();

        is($editor->{tab_manager}->tab_count(), 2, 'Tab was NOT closed after a failed save');
        is($editor->{tab_manager}->active_index(), 1, 'The dirty tab is still active');
        ok($editor->active_doc()->is_dirty(), 'Document is still marked dirty after the failed close attempt');
        ok($editor->{message_is_error}, 'An error message is surfaced for the failed save')
            or diag("message=" . ($editor->{message} // '(undef)'));
        like($editor->{message}, qr/save failed/i, 'Error message mentions the save failure');

        1;
    };
    my $err = $@;

    chmod 0700, $locked_dir;  # restore so tempdir cleanup can remove it
    ok($ok, 'Test body completed without dying') or diag("error: $err");
};

subtest 'cmd_close_tab: closing the last remaining tab quits instead of leaving a blank tab' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $file_a = create_temp_file("only file\n");

    my $editor = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    setup_editor_doc($editor, $file_a);

    is($editor->{tab_manager}->tab_count(), 1, 'Only one tab open');

    $editor->cmd_close_tab();

    is($editor->{state}, 'quit', 'Closing the last tab quits the editor');
    is($editor->{tab_manager}->tab_count(), 1,
        'The tab itself is left in place (quit short-circuits before remove_tab) — '
        . 'confirms this is a real quit, not "close then silently open a new blank tab"');

    # _do_close_tab saves the cursor position before checking tab_count,
    # even on the quit-the-last-tab path.
    my $abs_path = File::Spec->rel2abs($file_a);
    my $history = $store->get('history');
    ok(exists $history->{cursor_positions}{$abs_path},
        'Cursor position was recorded before quitting on the last tab');
};

# ============================================================================
# cmd_quit (bugs.md Scorecard round 3, same finding as above: "saves cursor
# position per tab before exit")
# ============================================================================
subtest 'cmd_quit saves cursor position for every open tab before exiting' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $file_a = create_temp_file("line a0\nline a1\nline a2\n");
    my $file_b = create_temp_file("line b0\nline b1\nline b2\n");

    my $editor = Zepto::Editor->new(terminal => mock_terminal(), state_store => $store);
    my (undef, $view_a) = setup_editor_doc($editor, $file_a);
    my (undef, $view_b) = setup_editor_doc($editor, $file_b);  # active

    $view_a->set_cursor(1, 3);
    $view_b->set_cursor(2, 1);

    is($editor->{tab_manager}->tab_count(), 2, 'Two clean tabs open');

    $editor->cmd_quit();

    is($editor->{state}, 'quit', 'cmd_quit transitions to quit state (no dirty tabs to confirm)');

    my $history = $store->get('history');
    my $positions = $history->{cursor_positions};

    my $abs_a = File::Spec->rel2abs($file_a);
    my $abs_b = File::Spec->rel2abs($file_b);

    is($positions->{$abs_a}{line}, 1, 'File A cursor line saved');
    is($positions->{$abs_a}{col}, 3, 'File A cursor col saved');
    is($positions->{$abs_b}{line}, 2, 'File B cursor line saved');
    is($positions->{$abs_b}{col}, 1, 'File B cursor col saved');
};

# ============================================================================
# cmd_next_tab / cmd_prev_tab / cmd_switch_to_tab
# ============================================================================
subtest 'cmd_next_tab / cmd_prev_tab wrap around the tab list' => sub {
    my $editor = Zepto::Editor->new(terminal => mock_terminal());
    my $file_a = create_temp_file("a\n");
    my $file_b = create_temp_file("b\n");
    my $file_c = create_temp_file("c\n");
    setup_editor_doc($editor, $file_a);
    setup_editor_doc($editor, $file_b);
    setup_editor_doc($editor, $file_c);  # active index 2

    $editor->{tab_manager}->set_active(0);
    is($editor->{tab_manager}->active_index(), 0, 'Starts on tab 0');

    $editor->cmd_next_tab();
    is($editor->{tab_manager}->active_index(), 1, 'cmd_next_tab moves to tab 1');

    $editor->cmd_next_tab();
    is($editor->{tab_manager}->active_index(), 2, 'cmd_next_tab moves to tab 2');

    $editor->cmd_next_tab();
    is($editor->{tab_manager}->active_index(), 0, 'cmd_next_tab wraps from last tab back to tab 0');

    $editor->cmd_prev_tab();
    is($editor->{tab_manager}->active_index(), 2, 'cmd_prev_tab wraps from tab 0 back to the last tab');

    $editor->cmd_prev_tab();
    is($editor->{tab_manager}->active_index(), 1, 'cmd_prev_tab moves back to tab 1');
};

subtest 'cmd_next_tab / cmd_prev_tab are no-ops with only one tab' => sub {
    my $editor = Zepto::Editor->new(terminal => mock_terminal());
    my $file_a = create_temp_file("a\n");
    setup_editor_doc($editor, $file_a);

    $editor->cmd_next_tab();
    is($editor->{tab_manager}->active_index(), 0, 'cmd_next_tab does nothing with a single tab');

    $editor->cmd_prev_tab();
    is($editor->{tab_manager}->active_index(), 0, 'cmd_prev_tab does nothing with a single tab');
};

subtest 'cmd_switch_to_tab jumps directly to a valid index and ignores invalid ones' => sub {
    my $editor = Zepto::Editor->new(terminal => mock_terminal());
    my $file_a = create_temp_file("a\n");
    my $file_b = create_temp_file("b\n");
    my $file_c = create_temp_file("c\n");
    setup_editor_doc($editor, $file_a);
    setup_editor_doc($editor, $file_b);
    setup_editor_doc($editor, $file_c);  # active index 2

    $editor->{tab_manager}->set_active(0);

    $editor->cmd_switch_to_tab(2);
    is($editor->{tab_manager}->active_index(), 2, 'cmd_switch_to_tab(2) jumps straight to tab 2');

    $editor->cmd_switch_to_tab(2);
    is($editor->{tab_manager}->active_index(), 2, 'cmd_switch_to_tab with the already-active index is a no-op');

    $editor->cmd_switch_to_tab(-1);
    is($editor->{tab_manager}->active_index(), 2, 'cmd_switch_to_tab(-1) is ignored (out of range)');

    $editor->cmd_switch_to_tab(99);
    is($editor->{tab_manager}->active_index(), 2, 'cmd_switch_to_tab(99) is ignored (out of range)');

    $editor->cmd_switch_to_tab(0);
    is($editor->{tab_manager}->active_index(), 0, 'cmd_switch_to_tab(0) jumps to tab 0');
};

# ============================================================================
# Simple toggle commands (lowest priority per bugs.md — included for
# completeness now that the higher-risk tab commands above are covered)
# ============================================================================
subtest 'cmd_select_all selects the entire active document' => sub {
    my $editor = Zepto::Editor->new(terminal => mock_terminal());
    my $file_a = create_temp_file("line one\nline two\nline three\n");
    setup_editor_doc($editor, $file_a);

    my $view = $editor->active_view();
    ok(!$view->has_selection(), 'No selection before cmd_select_all');

    $editor->cmd_select_all();

    ok($view->has_selection(), 'Selection exists after cmd_select_all');
    # Document does not keep a synthetic trailing empty line for a
    # newline-terminated file (line_count() is 3, not 4) — the trailing
    # newline is only re-added at save time (Document::save()).
    is($view->selected_text(), "line one\nline two\nline three",
        'Selected text covers the entire document');
};

subtest 'cmd_toggle_minimap flips the show_minimap preference' => sub {
    my $editor = Zepto::Editor->new(terminal => mock_terminal());
    my $file_a = create_temp_file("a\n");
    setup_editor_doc($editor, $file_a);

    my $initial = $editor->{prefs}->show_minimap();
    $editor->cmd_toggle_minimap();
    is($editor->{prefs}->show_minimap(), $initial ? 0 : 1, 'show_minimap flipped once');
    $editor->cmd_toggle_minimap();
    is($editor->{prefs}->show_minimap(), $initial, 'show_minimap flipped back');
};

subtest 'cmd_toggle_word_wrap flips the wrap override on the active view' => sub {
    my $editor = Zepto::Editor->new(terminal => mock_terminal());
    my $file_a = create_temp_file("a\n");
    setup_editor_doc($editor, $file_a);

    my $view = $editor->active_view();
    my $before = $editor->_effective_word_wrap();

    $editor->cmd_toggle_word_wrap();
    isnt($editor->_effective_word_wrap(), $before, 'Effective word wrap flipped once');

    $editor->cmd_toggle_word_wrap();
    is($editor->_effective_word_wrap(), $before, 'Effective word wrap flipped back');
};

subtest 'cmd_toggle_nerd_font flips the nerd_font preference' => sub {
    my $editor = Zepto::Editor->new(terminal => mock_terminal());
    my $file_a = create_temp_file("a\n");
    setup_editor_doc($editor, $file_a);

    my $initial = $editor->{prefs}->nerd_font();
    $editor->cmd_toggle_nerd_font();
    is($editor->{prefs}->nerd_font(), $initial ? 0 : 1, 'nerd_font flipped once');
    $editor->cmd_toggle_nerd_font();
    is($editor->{prefs}->nerd_font(), $initial, 'nerd_font flipped back');
};

done_testing();
