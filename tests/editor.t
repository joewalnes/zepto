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
use Zepto::CommandRegistry;

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

    $editor->do_find_next();

    # Cursor should be at end of first "foo" (with selection)
    ok($editor->active_view()->has_selection(), 'Match selected');
    like($editor->{message}, qr/Found/, 'Found message');
};

subtest 'Find not found' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);
    $editor->{search_term} = 'xyz';

    $editor->do_find_next();
    like($editor->{message}, qr/Not found/, 'Not found message');
};

subtest 'Find prev with selection finds previous match' => sub {
    my $term = mock_terminal();
    # Content: "foo bar foo baz foo"
    # Positions: col 0, col 8, col 16
    my $filename = create_temp_file("foo bar foo baz foo\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    setup_editor_doc($editor, $filename);
    $editor->{search_term} = 'foo';

    # Start at 0,0 - find_next searches from cursor+1
    # 1st find_next: search from 1, finds "foo" at 8
    # 2nd find_next: search from 12, finds "foo" at 16
    # 3rd find_next: search from 20 (end), wraps to find "foo" at 0
    $editor->do_find_next();  # Finds foo at col 8
    $editor->do_find_next();  # Finds foo at col 16
    $editor->do_find_next();  # Wraps around, finds foo at col 0

    # Now we have "foo" at position 0 selected (wrapped around)
    ok($editor->active_view()->has_selection(), 'Foo is selected');
    my ($sl, $sc, $el, $ec) = $editor->active_view()->selection();
    is($sc, 0, 'Selection at column 0 after wrap');

    # Find prev should find the "foo" at position 16 (searching backwards from -1, wraps)
    $editor->do_find_prev();
    ok($editor->active_view()->has_selection(), 'Previous foo is selected');
    ($sl, $sc, $el, $ec) = $editor->active_view()->selection();
    is($sc, 16, 'Find prev wrapped to foo at column 16');

    # Find prev again should find the "foo" at position 8
    $editor->do_find_prev();
    ($sl, $sc, $el, $ec) = $editor->active_view()->selection();
    is($sc, 8, 'Find prev found foo at column 8');

    # Find prev again should find the "foo" at position 0
    $editor->do_find_prev();
    ($sl, $sc, $el, $ec) = $editor->active_view()->selection();
    is($sc, 0, 'Find prev found foo at column 0');
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
# List continuation (Markdown / plain text) — CLAUDE.md Phase 2 item 5
# ============================================================================

subtest 'List continuation: dash bullet continues to new line' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();  # untitled — no grammar detected, counts as plain text
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "- first item");
    $view->set_cursor(0, length("- first item"));
    $editor->do_enter();

    is($doc->get_line_content(1), '- ', 'New line gets the same bullet marker');
    is($view->cursor_line(), 1, 'Cursor on new line');
    is($view->cursor_col(), 2, 'Cursor lands right after the marker');
};

subtest 'List continuation: star and plus bullets both work' => sub {
    my $term = mock_terminal();
    for my $bullet (qw(* +)) {
        my $editor = Zepto::Editor->new(terminal => mock_terminal());
        $editor->cmd_new_file();
        my $doc = $editor->active_doc();
        my $view = $editor->active_view();

        $doc->insert(0, "$bullet item text");
        $view->set_cursor(0, length("$bullet item text"));
        $editor->do_enter();

        is($doc->get_line_content(1), "$bullet ", "'$bullet' bullet continues with the same marker");
    }
};

subtest 'List continuation: blockquote continues' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "> quoted text");
    $view->set_cursor(0, length("> quoted text"));
    $editor->do_enter();

    is($doc->get_line_content(1), '> ', 'New line gets the blockquote marker');
};

subtest 'List continuation: numbered list increments' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "3. third item");
    $view->set_cursor(0, length("3. third item"));
    $editor->do_enter();

    is($doc->get_line_content(1), '4. ', 'Numbered marker increments (3. -> 4.)');
    is($view->cursor_col(), 3, 'Cursor lands after the incremented marker');
};

subtest 'List continuation: numbered list with paren separator increments' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "9) ninth item");
    $view->set_cursor(0, length("9) ninth item"));
    $editor->do_enter();

    is($doc->get_line_content(1), '10) ', 'Numbered marker increments and keeps the ) separator');
};

subtest 'List continuation: checkbox always continues unchecked' => sub {
    my $term = mock_terminal();
    for my $checkbox ('[ ]', '[x]', '[X]') {
        my $editor = Zepto::Editor->new(terminal => mock_terminal());
        $editor->cmd_new_file();
        my $doc = $editor->active_doc();
        my $view = $editor->active_view();

        my $line = "- $checkbox task text";
        $doc->insert(0, $line);
        $view->set_cursor(0, length($line));
        $editor->do_enter();

        is($doc->get_line_content(1), '- [ ] ', "Checkbox '$checkbox' continues as unchecked '- [ ] '");
    }
};

subtest 'List continuation: indented list item preserves indent' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "  - nested item");
    $view->set_cursor(0, length("  - nested item"));
    $editor->do_enter();

    is($doc->get_line_content(1), '  - ', 'New line keeps the 2-space indent plus the marker');
};

subtest 'List continuation: empty list item escapes the list' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    # Line is JUST the marker, nothing after it — pressing Enter here
    # should remove the marker and produce a plain blank line instead of
    # continuing the list indefinitely.
    $doc->insert(0, "- ");
    $view->set_cursor(0, 2);
    $editor->do_enter();

    is($doc->get_line_content(0), '', 'Marker removed from the (now-empty) original line');
    is($doc->get_line_content(1), '', 'New line has no marker — list escaped');
    is($view->cursor_line(), 1, 'Cursor on the new line');
    is($view->cursor_col(), 0, 'Cursor at column 0 (no indent, no marker)');
};

subtest 'List continuation: empty numbered item escapes with indent preserved' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "  1. ");
    $view->set_cursor(0, length("  1. "));
    $editor->do_enter();

    is($doc->get_line_content(0), '  ', 'Marker removed, indent preserved on original line');
    is($doc->get_line_content(1), '  ', 'New line keeps the indent but has no marker');
    is($view->cursor_col(), 2, 'Cursor lands after the preserved indent');
};

subtest 'List continuation: mid-line Enter does not insert a marker' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "- split here please");
    # Cursor in the middle of the text, not at EOL
    $view->set_cursor(0, length("- split he"));
    $editor->do_enter();

    is($doc->get_line_content(0), '- split he', 'First line truncated at cursor, no marker duplicated');
    is($doc->get_line_content(1), 're please', 'Second line is just the split remainder, no marker');
};

subtest 'List continuation: does not fire on a non-Markdown/non-plain-text file' => sub {
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.pl');
    print $fh "";
    close $fh;

    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();
    $editor->active_highlighter()->set_file($filename);

    $doc->insert(0, "- looks like a list but this is Perl");
    $view->set_cursor(0, length("- looks like a list but this is Perl"));
    $editor->do_enter();

    is($doc->get_line_content(1), '', 'No marker inserted on a detected non-Markdown language file');
    unlink $filename;
};

subtest 'List continuation: fires on a Markdown file' => sub {
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.md');
    print $fh "";
    close $fh;

    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    setup_editor_doc($editor, $filename);
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();
    $editor->active_highlighter()->set_file($filename);

    $doc->insert(0, "- a markdown list item");
    $view->set_cursor(0, length("- a markdown list item"));
    $editor->do_enter();

    is($doc->get_line_content(1), '- ', 'Marker continues on a detected Markdown file');
    unlink $filename;
};

subtest 'List continuation: disabled via continue_lists preference' => sub {
    my $term = mock_terminal();
    my $prefs = Zepto::Preferences->new();
    $prefs->set_continue_lists(0);
    my $editor = Zepto::Editor->new(terminal => $term, prefs => $prefs);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "- an item");
    $view->set_cursor(0, length("- an item"));
    $editor->do_enter();

    is($doc->get_line_content(1), '', 'No marker inserted when continue_lists preference is off');
};

subtest 'List continuation: does not fire during bracketed paste' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    $editor->cmd_new_file();
    my $doc = $editor->active_doc();
    my $view = $editor->active_view();

    $doc->insert(0, "- an item");
    $view->set_cursor(0, length("- an item"));
    $editor->{_bracketed_paste} = 1;
    $editor->do_enter();
    $editor->{_bracketed_paste} = 0;

    is($doc->get_line_content(1), '', 'No marker inserted during bracketed paste');
};

subtest 'cmd_toggle_continue_lists flips the preference and shows a status message' => sub {
    # Isolated state store — must not read/write the real
    # ~/.config/zepto (previous test runs would otherwise leave this
    # flaky, since a real StateStore persists and is shared/reloaded
    # across invocations).
    my $tmpdir = tempdir(CLEANUP => 1);
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );

    ok($editor->{prefs}->continue_lists(), 'continue_lists defaults to on');

    $editor->cmd_toggle_continue_lists();
    ok(!$editor->{prefs}->continue_lists(), 'First toggle turns it off');
    like($editor->{message}, qr/Continue Lists: OFF/, 'Status message shows OFF');

    $editor->cmd_toggle_continue_lists();
    ok($editor->{prefs}->continue_lists(), 'Second toggle turns it back on');
    like($editor->{message}, qr/Continue Lists: ON/, 'Status message shows ON');
};

subtest 'Continue Lists toggle state is reflected via CommandRegistry (palette [on]/[off])' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(
        terminal => $term,
        state_store => Zepto::StateStore->new(base_dir => $tmpdir),
    );
    my $cmd = Zepto::CommandRegistry->find_command('toggle_continue_lists');

    is(Zepto::CommandRegistry->get_toggle_display($cmd, $editor), 'on', 'Palette shows "on" by default');

    $editor->cmd_toggle_continue_lists();
    is(Zepto::CommandRegistry->get_toggle_display($cmd, $editor), 'off', 'Palette shows "off" after toggling');
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
# Cross-instance preference sync while idle (bugs.md/CLAUDE.md item 4:
# StateStore::check_for_changes previously only ran inside render(), so an
# idle instance — one that isn't typing and therefore isn't re-rendering —
# never noticed another window's preference changes at all)
# ============================================================================

subtest '_poll_cross_instance_prefs picks up an external preference change' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $prefs = Zepto::Preferences->new(state_store => $store);
    my $editor = Zepto::Editor->new(
        terminal     => mock_terminal(),
        state_store  => $store,
        prefs        => $prefs,
    );

    # Prime the cache so check_for_changes() has a baseline to compare
    # against (mirrors what init()/get() do in real startup).
    $store->get('preferences');
    is($editor->{state}, 'editing', 'sanity check: default state is editing');

    # Force the throttle window to have already elapsed.
    $editor->{_last_prefs_check_at} = 0;

    # Simulate a SECOND Zepto window writing a theme change to the shared
    # state file — same file, different process, from this instance's
    # point of view. sleep 1 for mtime resolution (StateStore relies on
    # mtime to detect external changes, matching state_store.t's own
    # "check_for_changes fires callback" test).
    sleep 1;
    open(my $fh, '>', "$tmpdir/preferences.json") or die $!;
    print $fh '{"theme":"light"}';
    close $fh;

    my $changed = $editor->_poll_cross_instance_prefs();
    ok($changed, '_poll_cross_instance_prefs reports a change was applied');
    is($prefs->theme(), 'light', 'Preferences listener actually applied the external change');
};

subtest '_poll_cross_instance_prefs is throttled — does not re-check every call' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $prefs = Zepto::Preferences->new(state_store => $store);
    my $editor = Zepto::Editor->new(
        terminal     => mock_terminal(),
        state_store  => $store,
        prefs        => $prefs,
    );
    $store->get('preferences');

    # First call sets the throttle timestamp to "now".
    $editor->{_last_prefs_check_at} = 0;
    $editor->_poll_cross_instance_prefs();
    my $set_at = $editor->{_last_prefs_check_at};
    ok($set_at > 0, 'Throttle timestamp was set');

    # A write immediately after should NOT be picked up by a second call
    # within the same throttle window (no artificial sleep here — this is
    # testing that the throttle itself, not mtime resolution, is what
    # blocks the second check).
    open(my $fh, '>', "$tmpdir/preferences.json") or die $!;
    print $fh '{"theme":"dark"}';
    close $fh;

    my $changed = $editor->_poll_cross_instance_prefs();
    ok(!$changed, 'Second call within the throttle window does not re-check');
    is($editor->{_last_prefs_check_at}, $set_at, 'Throttle timestamp unchanged — check_for_changes was skipped entirely');
};

subtest '_poll_cross_instance_prefs is a no-op outside STATE_EDITING' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $prefs = Zepto::Preferences->new(state_store => $store);
    my $editor = Zepto::Editor->new(
        terminal     => mock_terminal(),
        state_store  => $store,
        prefs        => $prefs,
    );
    $store->get('preferences');
    $editor->{_last_prefs_check_at} = 0;
    $editor->{state} = 'palette';

    sleep 1;
    open(my $fh, '>', "$tmpdir/preferences.json") or die $!;
    print $fh '{"theme":"light"}';
    close $fh;

    my $changed = $editor->_poll_cross_instance_prefs();
    ok(!$changed, 'No check performed while not in STATE_EDITING (e.g. palette open)');
};

done_testing();
