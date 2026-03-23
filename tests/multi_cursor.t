#!/usr/bin/env perl
# Tests for multi-cursor editing (Ctrl+D)
use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempfile);

use Zepto::Editor;
use Zepto::Terminal;
use Zepto::Document;
use Zepto::View;
use Zepto::FindEngine;
use Zepto::Highlighter;

sub mock_terminal {
    my ($in_fh, $in_name) = tempfile(UNLINK => 1);
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    return Zepto::Terminal->new(in => $in_fh, out => $out_fh);
}

sub create_editor_with_content {
    my ($content) = @_;
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $doc = Zepto::Document->new();
    $doc->insert(0, $content);
    my $view = Zepto::View->new(document => $doc);
    my $find_engine = Zepto::FindEngine->new(document => $doc);
    my $highlighter = Zepto::Highlighter->new();
    $editor->{tab_manager}->add_tab(
        document    => $doc,
        view        => $view,
        find_engine => $find_engine,
        highlighter => $highlighter,
        file_path   => undef,
    );
    return $editor;
}

# ============================================================================
subtest 'First Ctrl+D selects word under cursor' => sub {
    my $editor = create_editor_with_content("hello world hello\n");
    my $view = $editor->active_view();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();

    ok($view->has_selection(), 'Word is selected');
    is($view->selected_text(), 'hello', 'Selected word is "hello"');
    ok(!$view->has_multi_cursors(), 'No multi-cursors yet (just word select)');
};

# ============================================================================
subtest 'Second Ctrl+D adds next occurrence' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    my $view = $editor->active_view();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();  # Select "foo"
    $editor->cmd_select_next_occurrence();  # Add next "foo"

    ok($view->has_multi_cursors(), 'Multi-cursors active');
    is($view->cursor_count(), 2, 'Two cursors');
};

# ============================================================================
subtest 'Select all occurrences' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    my $view = $editor->active_view();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();  # Select "foo"
    $editor->cmd_select_next_occurrence();  # Add 2nd
    $editor->cmd_select_next_occurrence();  # Add 3rd

    is($view->cursor_count(), 3, 'Three cursors for three occurrences');
};

# ============================================================================
subtest 'Multi-cursor insert replaces selection at all positions' => sub {
    my $editor = create_editor_with_content("ab cd ab ef ab\n");
    my $view = $editor->active_view();
    my $doc = $editor->active_doc();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();  # Select "ab"
    $editor->cmd_select_next_occurrence();  # Add 2nd
    $editor->cmd_select_next_occurrence();  # Add 3rd

    is($view->cursor_count(), 3, 'Three cursors');

    # Type replacement
    $editor->do_insert_char('X');
    $editor->do_insert_char('Y');

    is($doc->text(), "XY cd XY ef XY\n", 'All occurrences replaced');
};

# ============================================================================
subtest 'Multi-cursor backspace works at all positions' => sub {
    my $editor = create_editor_with_content("ab cd ab ef ab\n");
    my $view = $editor->active_view();
    my $doc = $editor->active_doc();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();  # Select "ab"
    $editor->cmd_select_next_occurrence();  # Add 2nd
    $editor->cmd_select_next_occurrence();  # Add 3rd

    # Backspace deletes selections
    $editor->do_backspace();

    is($doc->text(), " cd  ef \n", 'All selections deleted');
};

# ============================================================================
subtest 'Multi-cursor insert then backspace' => sub {
    my $editor = create_editor_with_content("aa bb aa\n");
    my $view = $editor->active_view();
    my $doc = $editor->active_doc();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();  # Select "aa"
    $editor->cmd_select_next_occurrence();  # Add 2nd

    # Type, then backspace
    $editor->do_insert_char('Z');
    $editor->do_backspace();

    is($doc->text(), " bb \n", 'Typed then backspaced at all cursors');
};

# ============================================================================
subtest 'Escape clears multi-cursors' => sub {
    my $editor = create_editor_with_content("foo bar foo\n");
    my $view = $editor->active_view();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();
    $editor->cmd_select_next_occurrence();

    ok($view->has_multi_cursors(), 'Multi-cursors before escape');

    # Simulate Escape
    $editor->handle_event({ type => 'key', key => 'escape' });

    ok(!$view->has_multi_cursors(), 'Multi-cursors cleared after escape');
};

# ============================================================================
subtest 'Arrow key clears multi-cursors' => sub {
    my $editor = create_editor_with_content("foo bar foo\n");
    my $view = $editor->active_view();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();
    $editor->cmd_select_next_occurrence();

    ok($view->has_multi_cursors(), 'Multi-cursors before arrow');

    $editor->handle_event({ type => 'key', key => 'right' });

    ok(!$view->has_multi_cursors(), 'Multi-cursors cleared after arrow');
};

# ============================================================================
subtest 'Multi-cursor across multiple lines' => sub {
    my $editor = create_editor_with_content("name = 1\nname = 2\nname = 3\n");
    my $view = $editor->active_view();
    my $doc = $editor->active_doc();

    $view->set_cursor(0, 0);
    $editor->cmd_select_next_occurrence();  # Select "name" on line 0
    $editor->cmd_select_next_occurrence();  # Add line 1
    $editor->cmd_select_next_occurrence();  # Add line 2

    is($view->cursor_count(), 3, 'Three cursors on three lines');

    # Replace
    $editor->do_insert_char('v');

    is($doc->text(), "v = 1\nv = 2\nv = 3\n", 'Multi-line replacement works');
};

done_testing();
