#!/usr/bin/env perl
# Tests for Zepto::Editor
use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempfile tempdir);

use Zepto::Editor;
use Zepto::Terminal;
use Zepto::Document;
use Zepto::View;
use Zepto::Preferences;

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
    is($editor->{file_path}, $filename, 'File path set');
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
    is(Zepto::Editor::STATE_MENU, 'menu', 'STATE_MENU');
    is(Zepto::Editor::STATE_DIALOG, 'dialog', 'STATE_DIALOG');
    is(Zepto::Editor::STATE_PROMPT, 'prompt', 'STATE_PROMPT');
    is(Zepto::Editor::STATE_FOOTER_INPUT, 'footer_input', 'STATE_FOOTER_INPUT');
    is(Zepto::Editor::STATE_FILE_PICKER, 'file_picker', 'STATE_FILE_PICKER');
    is(Zepto::Editor::STATE_FIND, 'find', 'STATE_FIND');
    is(Zepto::Editor::STATE_QUIT, 'quit', 'STATE_QUIT');
};

# ============================================================================
# Menu operations
# ============================================================================
subtest 'Open menu' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->open_menu('f');
    is($editor->{state}, 'menu', 'State is menu');
    is($editor->{menu_open}, 'f', 'File menu open');
    is($editor->{menu_selected}, 0, 'First item selected');
};

subtest 'Close menu' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->open_menu('e');
    $editor->close_menu();
    is($editor->{state}, 'editing', 'State is editing');
    is($editor->{menu_open}, undef, 'Menu closed');
};

subtest 'Navigate menus' => sub {
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);

    $editor->open_menu('f');
    $editor->next_menu();
    is($editor->{menu_open}, 'e', 'Next menu is Edit');

    $editor->next_menu();
    is($editor->{menu_open}, 's', 'Next menu is Search');

    $editor->prev_menu();
    is($editor->{menu_open}, 'e', 'Prev menu is Edit');
};

subtest 'Click on menu item' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    my $filename = create_temp_file("test content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Open the Edit menu
    $editor->open_menu('e');
    is($editor->{state}, 'menu', 'Menu is open');

    # Get the position of the Edit menu dropdown
    my $positions = Zepto::Renderer::get_menu_positions();
    my $menu_x = $positions->{e}{x};

    # Simulate clicking on the first item (Undo) - row 2, within menu x bounds
    my $event = {
        type => 'mouse',
        action => 'press',
        x => $menu_x + 2,  # Inside the dropdown
        y => 2,            # First item row
    };
    $editor->handle_menu_event($event);

    # Menu should have closed after executing item
    is($editor->{state}, 'editing', 'Menu closed after clicking item');
};

subtest 'Click outside menu closes it' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("test content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Open the File menu
    $editor->open_menu('f');
    is($editor->{state}, 'menu', 'Menu is open');

    # Simulate clicking outside the menu dropdown (far right)
    my $event = {
        type => 'mouse',
        action => 'press',
        x => 70,  # Far outside menu
        y => 5,   # Below menu items
    };
    $editor->handle_menu_event($event);

    # Menu should have closed
    is($editor->{state}, 'editing', 'Menu closed after clicking outside');
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
    ok($editor->{message_time} > 0, 'Message time set');
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
    my $editor = Zepto::Editor->new(terminal => $term);

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
    is($editor->{file_path}, $filename, 'File path stored');
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
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Test undo when nothing to undo
    $editor->cmd_undo();
    like($editor->{message}, qr/undo/i, 'Undo message');

    # Test redo when nothing to redo
    $editor->cmd_redo();
    like($editor->{message}, qr/redo/i, 'Redo message');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Create selection
    $editor->{view}->move_right() for (1..5);  # Move to space after Hello
    $editor->{view}->move_right(1) for (1..6); # Select " World"

    ok($editor->{view}->has_selection(), 'Selection active');

    $editor->delete_selection();
    ok(!$editor->{view}->has_selection(), 'Selection cleared');
    is($editor->{document}->text(), 'Hello', 'Selection deleted');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->do_indent();
    like($editor->{document}->text(), qr/^    line/, 'Line indented with spaces');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->do_indent();
    like($editor->{document}->text(), qr/^\tline/, 'Line indented with tab');
};

subtest 'Indent preserves selection' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line1\nline2\nline3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Select lines 1-2 (0-indexed: lines 0-1)
    $editor->{view}->set_cursor(0, 0, 0);
    $editor->{view}->set_cursor(1, 5, 1);  # Select to end of "line2"

    ok($editor->{view}->has_selection(), 'Selection active before indent');

    $editor->do_indent();

    ok($editor->{view}->has_selection(), 'Selection preserved after indent');
    like($editor->{document}->text(), qr/^    line1\n    line2\n/, 'Lines indented');
};

subtest 'Unindent preserves selection' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("    line1\n    line2\nline3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Select lines 1-2 (0-indexed: lines 0-1)
    $editor->{view}->set_cursor(0, 4, 0);  # Start at "l" in "line1"
    $editor->{view}->set_cursor(1, 9, 1);  # Select to end of "    line2"

    ok($editor->{view}->has_selection(), 'Selection active before unindent');

    $editor->do_unindent();

    ok($editor->{view}->has_selection(), 'Selection preserved after unindent');
    like($editor->{document}->text(), qr/^line1\nline2\n/, 'Lines unindented');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Cursor on first line
    is($editor->{view}->cursor_line(), 0, 'Start on line 0');

    $editor->do_move_line_down();

    is($editor->{document}->text(), "bbb\naaa\nccc", 'Line moved down');
    is($editor->{view}->cursor_line(), 1, 'Cursor follows moved line');
};

subtest 'Move line up' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\nccc\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Move cursor to second line
    $editor->{view}->move_down();
    is($editor->{view}->cursor_line(), 1, 'Start on line 1');

    $editor->do_move_line_up();

    is($editor->{document}->text(), "bbb\naaa\nccc", 'Line moved up');
    is($editor->{view}->cursor_line(), 0, 'Cursor follows moved line');
};

subtest 'Move line at boundary is no-op' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Try to move first line up - should be no-op
    $editor->do_move_line_up();
    is($editor->{document}->text(), "aaa\nbbb", 'First line stays put');

    # Move to last line, try to move down - should be no-op
    $editor->{view}->move_down();
    $editor->do_move_line_down();
    is($editor->{document}->text(), "aaa\nbbb", 'Last line stays put');
};

subtest 'Move multiple selected lines' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\nccc\nddd\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Select lines 1-2 (bbb, ccc)
    $editor->{view}->move_down();  # Line 1
    $editor->{view}->set_cursor(1, 0, 0);
    $editor->{view}->set_cursor(2, 3, 1);  # Partial selection of line 2

    $editor->do_move_line_down();

    is($editor->{document}->text(), "aaa\nddd\nbbb\nccc", 'Selected lines moved down');
    ok($editor->{view}->has_selection(), 'Selection preserved');
};

subtest 'Duplicate line down' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->do_duplicate_line_down();

    is($editor->{document}->text(), "aaa\naaa\nbbb", 'Line duplicated below');
    is($editor->{view}->cursor_line(), 1, 'Cursor on new duplicate');
};

subtest 'Duplicate line up' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("aaa\nbbb\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->{view}->move_down();  # Line 1

    $editor->do_duplicate_line_up();

    is($editor->{document}->text(), "aaa\nbbb\nbbb", 'Line duplicated above');
    is($editor->{view}->cursor_line(), 1, 'Cursor on new duplicate');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Select "Hello"
    $editor->{view}->move_right(1) for (1..5);

    $editor->cmd_copy();
    is($editor->{clipboard}, 'Hello', 'Text copied');

    # Move to end
    $editor->{view}->move_to_document_end();
    $editor->{view}->move_to_line_end();

    $editor->cmd_paste();
    is($editor->{document}->text(), 'Hello WorldHello', 'Text pasted');
};

subtest 'Copy without selection copies current line' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line one\nline two\nline three\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Position cursor on line two, no selection
    $editor->{view}->move_down();
    ok(!$editor->{view}->has_selection(), 'No selection initially');

    $editor->cmd_copy();

    # Should have selected and copied the entire line including newline
    ok($editor->{view}->has_selection(), 'Line is now selected');
    is($editor->{clipboard}, "line two\n", 'Entire line copied including newline');
    is($editor->{view}->cursor_line(), 1, 'Cursor stays on same line');
    is($editor->{view}->cursor_col(), 8, 'Cursor at end of line');
};

subtest 'Cut without selection cuts current line' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("line one\nline two\nline three\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Position cursor on line two, no selection
    $editor->{view}->move_down();
    ok(!$editor->{view}->has_selection(), 'No selection initially');

    $editor->cmd_cut();

    # Line should be cut
    is($editor->{clipboard}, "line two\n", 'Entire line cut including newline');
    is($editor->{document}->text(), "line one\nline three", 'Line removed from document');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});
    $editor->{search_term} = 'foo';

    $editor->do_find_next();

    # Cursor should be at end of first "foo" (with selection)
    ok($editor->{view}->has_selection(), 'Match selected');
    like($editor->{message}, qr/Found/, 'Found message');
};

subtest 'Find not found' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});
    $editor->{search_term} = 'foo';

    # Start at 0,0 - find_next searches from cursor+1
    # 1st find_next: search from 1, finds "foo" at 8
    # 2nd find_next: search from 12, finds "foo" at 16
    # 3rd find_next: search from 20 (end), wraps to find "foo" at 0
    $editor->do_find_next();  # Finds foo at col 8
    $editor->do_find_next();  # Finds foo at col 16
    $editor->do_find_next();  # Wraps around, finds foo at col 0

    # Now we have "foo" at position 0 selected (wrapped around)
    ok($editor->{view}->has_selection(), 'Foo is selected');
    my ($sl, $sc, $el, $ec) = $editor->{view}->selection();
    is($sc, 0, 'Selection at column 0 after wrap');

    # Find prev should find the "foo" at position 16 (searching backwards from -1, wraps)
    $editor->do_find_prev();
    ok($editor->{view}->has_selection(), 'Previous foo is selected');
    ($sl, $sc, $el, $ec) = $editor->{view}->selection();
    is($sc, 16, 'Find prev wrapped to foo at column 16');

    # Find prev again should find the "foo" at position 8
    $editor->do_find_prev();
    ($sl, $sc, $el, $ec) = $editor->{view}->selection();
    is($sc, 8, 'Find prev found foo at column 8');

    # Find prev again should find the "foo" at position 0
    $editor->do_find_prev();
    ($sl, $sc, $el, $ec) = $editor->{view}->selection();
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
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->{document}->line_count());

    # Simulate press at column 6 (start of "World")
    # Row 3 is the first text line (after menu bar on 1 and ruler bar on 2)
    # Terminal coordinates are 1-indexed, so x = gutter_width + col + 1
    my $x_start = $gutter_width + 6 + 1;  # gutter + col 6 + 1 for 1-indexed
    my $press = { type => 'mouse', action => 'press', x => $x_start, y => 3, modifiers => [] };
    $editor->handle_mouse_event($press);

    ok(!$editor->{view}->has_selection(), 'No selection after press');
    is($editor->{view}->cursor_col(), 6, 'Cursor at column 6 after press');

    # Simulate drag to column 11 (end of "World")
    my $x_end = $gutter_width + 11 + 1;  # gutter + col 11 + 1 for 1-indexed
    my $drag = { type => 'mouse', action => 'drag', x => $x_end, y => 3, modifiers => [] };
    $editor->handle_mouse_event($drag);

    ok($editor->{view}->has_selection(), 'Selection exists after drag');
    my ($sl, $sc, $el, $ec) = $editor->{view}->selection();
    is($sc, 6, 'Selection starts at column 6');
    is($ec, 11, 'Selection ends at column 11');
    is($editor->{view}->selected_text(), 'World', 'Selected text is "World"');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Simulate goto line 2
    $editor->{view}->set_cursor(1, 0);  # Line 2 (0-indexed)
    is($editor->{view}->cursor_line(), 1, 'Cursor on line 2');
};

subtest 'Goto line uses footer input' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->cmd_goto_line();

    is($editor->{state}, 'footer_input', 'Goto line uses footer input, not dialog');
    ok($editor->{footer_input}, 'Footer input is set');
    like($editor->{footer_input}{prompt}, qr/Go to/i, 'Prompt mentions go to');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->cmd_goto_line();
    $editor->handle_input('3');
    $editor->handle_input("\r");  # Enter

    is($editor->{view}->cursor_line(), 2, 'Line 3 is 0-indexed line 2');
    is($editor->{view}->cursor_col(), 0, 'Column is 0');
};

subtest 'Goto line 0 goes to line 1' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Start on line 2
    $editor->{view}->set_cursor(1, 3);

    $editor->cmd_goto_line();
    $editor->handle_input('0');
    $editor->handle_input("\r");

    is($editor->{view}->cursor_line(), 0, 'Line 0 input goes to first line');
    is($editor->{view}->cursor_col(), 0, 'Column is 0');
};

subtest 'Goto line:col parses column' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2 with more text\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->cmd_goto_line();
    $editor->handle_input('2:10');
    $editor->handle_input("\r");

    is($editor->{view}->cursor_line(), 1, 'Line 2 is 0-indexed line 1');
    is($editor->{view}->cursor_col(), 9, 'Column 10 is 0-indexed column 9');
};

subtest 'Goto :col jumps to column on current line' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2 with more text\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Start on line 2 (0-indexed: 1), column 0
    $editor->{view}->set_cursor(1, 0);

    $editor->cmd_goto_line();
    $editor->handle_input(':15');
    $editor->handle_input("\r");

    is($editor->{view}->cursor_line(), 1, 'Stays on current line');
    is($editor->{view}->cursor_col(), 14, 'Column 15 is 0-indexed column 14');
};

subtest 'Goto line clamps to valid range' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Line 1\nLine 2\nLine 3\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Go to line way beyond end
    $editor->cmd_goto_line();
    $editor->handle_input('999');
    $editor->handle_input("\r");

    my $max_line = $editor->{document}->line_count() - 1;
    is($editor->{view}->cursor_line(), $max_line, 'Line clamped to max');
};

subtest 'Goto line:col clamps column to line length' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Short\nLine 2\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->cmd_goto_line();
    $editor->handle_input('1:999');
    $editor->handle_input("\r");

    is($editor->{view}->cursor_line(), 0, 'On line 1');
    is($editor->{view}->cursor_col(), 5, 'Column clamped to line length (5 chars in "Short")');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Arrow keys
    $editor->handle_input("\x1b[A");  # Up
    is($editor->{state}, 'editing', 'Still editing after up arrow');

    $editor->handle_input("\x1b[B");  # Down
    is($editor->{state}, 'editing', 'Still editing after down arrow');

    # Mouse events (SGR format)
    $editor->handle_input("\x1b[<0;10;5M");  # Mouse press
    is($editor->{state}, 'editing', 'Still editing after mouse event');

    # Lone escape opens menu (new behavior)
    $editor->handle_input("\x1b");
    is($editor->{state}, 'menu', 'Lone escape opens menu');
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
        $editor->{document} = Zepto::Document->load($filename);
        $editor->{view} = Zepto::View->new(document => $editor->{document});

        my $char = chr($ctrl);
        $editor->handle_input($char);
        isnt($editor->{state}, 'quit', "Ctrl+" . chr(ord('a') + $ctrl - 1) . " doesn't quit");
    }

    # Test Ctrl+Q (chr(17)) - should trigger quit on clean document
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->handle_input("\x11");  # Ctrl+Q
    is($editor->{state}, 'quit', 'Ctrl+Q triggers quit');

    # Test Ctrl+W (chr(23)) - save and quit on clean document
    $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Make document dirty
    $editor->{document}->insert(0, 'x');
    ok($editor->{document}->is_dirty(), 'Document is dirty');

    # First Ctrl+Q should NOT quit (just show warning)
    $editor->handle_input("\x11");
    is($editor->{state}, 'editing', 'First Ctrl+Q on dirty doc stays editing');
    is($editor->{quit_pending}, 1, 'Quit is pending');
    like($editor->{message}, qr/unsaved/i, 'Warning message shown');

    # Second Ctrl+Q should quit
    $editor->handle_input("\x11");
    is($editor->{state}, 'quit', 'Second Ctrl+Q quits');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Document is clean, should create new immediately
    $editor->cmd_new_file();

    is($editor->{document}->text(), '', 'Document is now empty');
    is($editor->{file_path}, undef, 'File path cleared');
    like($editor->{message}, qr/new file/i, 'New file message shown');
};

subtest 'New file on dirty document shows prompt' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Original\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Make dirty
    $editor->{document}->insert(0, 'x');
    ok($editor->{document}->is_dirty(), 'Document is dirty');

    $editor->cmd_new_file();

    is($editor->{state}, 'prompt', 'Prompt state activated');
    ok($editor->{prompt}, 'Prompt is set');
    like($editor->{prompt}{text}, qr/unsaved/i, 'Prompt shows unsaved message');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->cmd_open_file();

    is($editor->{state}, 'file_picker', 'File picker state activated');
    ok($editor->{file_picker}, 'File picker is set');
};

subtest 'Open file on dirty document shows prompt first' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Original\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Make dirty
    $editor->{document}->insert(0, 'x');

    $editor->cmd_open_file();

    is($editor->{state}, 'prompt', 'Prompt state activated first');
    ok(!$editor->{file_picker}, 'File picker not yet opened');
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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

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

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    my $choice_made = 'not_called';
    $editor->open_prompt(
        text => 'Test',
        options => [{ key => 'y', label => 'Yes' }],
        on_select => sub { $choice_made = shift; },
    );

    # Press escape
    $editor->handle_input("\e");

    is($choice_made, 'not_called', 'Callback not called on escape');
    is($editor->{state}, 'editing', 'Back to editing state');
};

# ============================================================================
# File picker handling
# ============================================================================
subtest 'File picker navigation' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->cmd_open_file();
    ok($editor->{file_picker}, 'File picker opened');

    my $initial = $editor->{file_picker}->selected();

    # Arrow down
    $editor->handle_input("\e[B");  # Down arrow
    is($editor->{file_picker}->selected(), $initial + 1, 'Down arrow moves selection');

    # Arrow up
    $editor->handle_input("\e[A");  # Up arrow
    is($editor->{file_picker}->selected(), $initial, 'Up arrow moves selection back');
};

subtest 'File picker typing filters' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->cmd_open_file();
    my $initial_count = $editor->{file_picker}->filtered_count();

    # Type to filter
    $editor->handle_input('xyz');  # Unlikely to match much

    my $new_count = $editor->{file_picker}->filtered_count();
    ok($new_count <= $initial_count, 'Typing filters results');
    is($editor->{file_picker}->query(), 'xyz', 'Query updated');
};

subtest 'File picker escape closes' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(
        terminal => $term,
        file => $filename,
    );

    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->cmd_open_file();
    is($editor->{state}, 'file_picker', 'File picker open');

    $editor->handle_input("\e");  # Escape
    is($editor->{state}, 'editing', 'Back to editing after escape');
    ok(!$editor->{file_picker}, 'File picker cleared');
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
    is($editor->{footer_input}{value}, 'initial', 'Initial value set');

    $editor->close_footer_input();
    is($editor->{state}, 'editing', 'Back to editing');
    is($editor->{footer_input}, undef, 'Footer input cleared');
};

subtest 'Footer input handles typing' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    $editor->open_footer_input(prompt => 'Name:');
    is($editor->{footer_input}{value}, '', 'Value initially empty');

    # Type characters
    $editor->handle_input('a');
    is($editor->{footer_input}{value}, 'a', 'Char added');

    $editor->handle_input('bc');
    is($editor->{footer_input}{value}, 'abc', 'More chars added');

    # Backspace
    $editor->handle_input("\x7f");  # DEL/backspace
    is($editor->{footer_input}{value}, 'ab', 'Backspace works');
};

subtest 'Footer input submit calls callback' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

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
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    my $cancelled = 0;
    $editor->open_footer_input(
        prompt => 'Name:',
        on_cancel => sub { $cancelled = 1; },
    );

    $editor->handle_input('partial');
    $editor->handle_input("\e");  # Escape

    is($cancelled, 1, 'Cancel callback called');
    is($editor->{state}, 'editing', 'Back to editing after cancel');
};

# ============================================================================
# Menu bar Open button
# ============================================================================
subtest 'Click Open button in menu bar' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    my $filename = create_temp_file("Content\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    # Render once to set up button positions
    # We need to manually trigger the rendering to populate button positions
    my $cols = 80;
    Zepto::Renderer->_render_menu_bar($editor->{theme}, $cols, {});

    my @buttons = Zepto::Renderer::get_menu_bar_buttons();
    ok(scalar(@buttons) >= 3, 'At least 3 buttons (Open, Save, Quit)');

    # Find the Open button
    my ($open_btn) = grep { $_->{action} eq 'open' } @buttons;
    ok($open_btn, 'Open button exists');

    # Click on it
    my $x = int(($open_btn->{x_start} + $open_btn->{x_end}) / 2);
    $editor->handle_menu_click($x);

    is($editor->{state}, 'file_picker', 'Clicking Open button opens file picker');
};

# ============================================================================
# Mouse button tracking (spurious drag prevention)
# ============================================================================
subtest 'Mouse button state tracking' => sub {
    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

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
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->{document}->line_count());

    # Ensure mouse button is up
    is($editor->{mouse_button_down}, 0, 'Mouse button initially up');
    ok(!$editor->{view}->has_selection(), 'No selection initially');

    # Send drag event without press first (spurious motion)
    my $drag = { type => 'mouse', action => 'drag', x => $gutter_width + 5, y => 2, modifiers => [] };
    $editor->handle_mouse_event($drag);

    # Should NOT create selection
    ok(!$editor->{view}->has_selection(), 'No selection after spurious drag');
};

subtest 'Drag after press creates selection' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    my $filename = create_temp_file("Hello World\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->{document}->line_count());

    # Press first
    my $press = { type => 'mouse', action => 'press', x => $gutter_width + 0, y => 2, modifiers => [] };
    $editor->handle_mouse_event($press);
    is($editor->{mouse_button_down}, 1, 'Mouse button down');

    # Then drag
    my $drag = { type => 'mouse', action => 'drag', x => $gutter_width + 5, y => 2, modifiers => [] };
    $editor->handle_mouse_event($drag);

    # Should create selection
    ok($editor->{view}->has_selection(), 'Selection created after proper press+drag');
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
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->{document}->line_count());

    # Click at display column 4 (where 'b' visually appears)
    # Terminal coordinates are 1-indexed, so x = gutter_width + display_col + 1
    # Row 3 is the first text line (after menu bar on 1 and ruler bar on 2)
    my $display_col = 4;  # Where 'b' appears visually
    my $x = $gutter_width + $display_col + 1;
    my $press = { type => 'mouse', action => 'press', x => $x, y => 3, modifiers => [] };
    $editor->handle_mouse_event($press);

    # Cursor should be at document column 2 (after 'a' and tab), not display column 4
    is($editor->{view}->cursor_col(), 2, 'Cursor at doc column 2 (after a and tab), not display column 4');
};

subtest 'Mouse click in middle of tab jumps to tab position' => sub {
    use Zepto::Renderer;

    my $term = mock_terminal();
    # Content: "a\tb" - clicking in the middle of the tab's visual space
    my $filename = create_temp_file("a\tb\n");
    my $editor = Zepto::Editor->new(terminal => $term, file => $filename);
    $editor->{document} = Zepto::Document->load($filename);
    $editor->{view} = Zepto::View->new(document => $editor->{document});

    my $gutter_width = Zepto::Renderer->get_gutter_width($editor->{document}->line_count());

    # Click at display column 2 (in the middle of the tab's visual space, columns 1-3)
    my $display_col = 2;
    my $x = $gutter_width + $display_col + 1;
    my $press = { type => 'mouse', action => 'press', x => $x, y => 3, modifiers => [] };
    $editor->handle_mouse_event($press);

    # Cursor should be at document column 1 (the tab character position)
    is($editor->{view}->cursor_col(), 1, 'Clicking in tab space positions cursor at tab character');
};

done_testing();
