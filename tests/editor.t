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
    like($editor->{document}->text(), qr/^Hello\n/, 'Selection deleted');
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
    like($editor->{document}->text(), qr/Hello World\nHello/, 'Text pasted');
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

    my $gutter_width = Zepto::Renderer::get_gutter_width($editor->{document}->line_count());

    # Simulate press at column 6 (start of "World")
    my $x_start = $gutter_width + 1 + 6;  # gutter + separator + col 6
    my $press = { type => 'mouse', action => 'press', x => $x_start, y => 2, modifiers => [] };
    $editor->handle_mouse_event($press);

    ok(!$editor->{view}->has_selection(), 'No selection after press');
    is($editor->{view}->cursor_col(), 6, 'Cursor at column 6 after press');

    # Simulate drag to column 11 (end of "World")
    my $x_end = $gutter_width + 1 + 11;
    my $drag = { type => 'mouse', action => 'drag', x => $x_end, y => 2, modifiers => [] };
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

done_testing();
