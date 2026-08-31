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

# ============================================================================
# QA-REG-203: backspace across a line-join must correctly reposition a
# not-yet-processed secondary cursor on the joined-away line, shifting
# both its line AND its column (not just its line). Regression for
# bugs.md P1 "Multi-cursor backspace/insert desyncs secondary cursor
# positions across line-joins".
subtest 'Multi-cursor backspace across line-join repositions other cursor (QA-REG-203)' => sub {
    my $editor = create_editor_with_content("hello\nworld\n");
    my $view = $editor->active_view();
    my $doc = $editor->active_doc();

    # Primary cursor at (1,0): backspacing here joins line 1 into line 0.
    $view->set_cursor(1, 0);
    # Secondary cursor at (1,3): on the same line being joined away.
    $view->add_multi_cursor(line => 1, col => 3);

    is($view->cursor_count(), 2, 'Two cursors before backspace');

    $editor->do_backspace();

    is($doc->text(), "hellowold\n", 'Line-join backspace produced correct document text');

    my @positions = sort { $a->{line} <=> $b->{line} || $a->{col} <=> $b->{col} }
        $view->all_cursors_sorted();
    is(scalar(@positions), 2, 'Still two cursors after backspace');

    # The cursor that was at (1,0) joins onto line 0 at col 5 (end of
    # "hello"). The cursor that was at (1,3) first does its own backspace
    # on "world" (deleting the 'r', moving to col 2 of "wold"), then gets
    # shifted onto line 0 at col 5+2=7 by the line-join. Pre-fix, this
    # cursor incorrectly landed at (0,2) -- pointing into "hello" instead
    # of "hellowold".
    is($positions[0]{line}, 0, 'First cursor on line 0 after join');
    is($positions[0]{col}, 5, 'Join-point cursor lands at col 5 (end of "hello")');
    is($positions[1]{line}, 0, 'Second cursor on line 0 after join');
    is($positions[1]{col}, 7, 'Other cursor correctly repositioned to col 7, not corrupted');
};

# ============================================================================
# QA-REG-204: deleting a multi-line selection at one cursor must shift the
# line number (not the column) of a not-yet-processed plain cursor located
# below the deleted range, while leaving its column untouched (since the
# deletion doesn't touch that cursor's own line content). Regression for
# bugs.md P1 "...multi-line-selection deletes".
subtest 'Multi-cursor backspace with multi-line selection repositions cursor below (QA-REG-204)' => sub {
    my $editor = create_editor_with_content("aaaa\nbbbb\ncccc\ndddd\n");
    my $view = $editor->active_view();
    my $doc = $editor->active_doc();

    # Primary cursor: a forward multi-line selection from (0,2) to (2,2),
    # spanning lines 0-2.
    $view->set_cursor(0, 2);
    $view->set_cursor(2, 2, 1);   # extend selection down to line 2

    # Secondary plain cursor on line 3, below the selection.
    $view->add_multi_cursor(line => 3, col => 2);

    is($view->cursor_count(), 2, 'Two cursors before backspace');
    ok($view->has_selection(), 'Primary cursor has an active multi-line selection');

    $editor->do_backspace();

    # The multi-line selection (0,2)-(2,2) is deleted, collapsing lines
    # 0-2 into a single line "aacc". The secondary cursor's own backspace
    # (at its own position, line 3 col 2) also runs, turning "dddd" into
    # "ddd" and its own col into 1 -- then that surviving line shifts up
    # by 2 lines (2 lines were removed by the selection delete).
    is($doc->text(), "aacc\nddd\n", 'Multi-line selection delete + own backspace produced correct text');

    my @positions = sort { $a->{line} <=> $b->{line} || $a->{col} <=> $b->{col} }
        $view->all_cursors_sorted();
    is(scalar(@positions), 2, 'Still two cursors after backspace');
    is($positions[0]{line}, 0, 'Selection cursor collapsed to line 0');
    is($positions[0]{col}, 2, 'Selection cursor collapsed to col 2');
    is($positions[1]{line}, 1, 'Cursor below the deleted range shifted up by the 2 removed lines');
    is($positions[1]{col}, 1, 'Cursor below the deleted range keeps its own (post-backspace) column');
};

done_testing();
