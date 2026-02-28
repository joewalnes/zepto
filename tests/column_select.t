#!/usr/bin/env perl
# Tests for column (rectangular) selection mode
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Zepto::Document;
use Zepto::View;

# Helper to create doc+view
sub make_view {
    my ($text, %opts) = @_;
    my $doc = Zepto::Document->new(text => $text);
    my $view = Zepto::View->new(
        document => $doc,
        viewport_rows => $opts{rows} // 10,
        viewport_cols => $opts{cols} // 40,
    );
    return ($doc, $view);
}

# ============================================================================
# Phase 1: Selection Model
# ============================================================================

subtest 'Column select defaults to off' => sub {
    my ($doc, $view) = make_view("hello\nworld");
    ok(!$view->column_select(), 'column_select is false initially');
};

subtest 'start_column_selection enables column mode' => sub {
    my ($doc, $view) = make_view("hello\nworld");
    $view->set_cursor(0, 2);
    $view->start_column_selection();

    ok($view->column_select(), 'column_select is true');
    ok($view->has_selection(), 'has_selection is true');

    # Anchor should be at current cursor position
    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 0, 'anchor line');
    is($left, 2, 'anchor col');
    is($bottom, 0, 'cursor line');
    is($right, 2, 'cursor col (zero-width)');
};

subtest 'clear_selection resets column_select' => sub {
    my ($doc, $view) = make_view("hello\nworld");
    $view->set_cursor(0, 2);
    $view->start_column_selection();
    ok($view->column_select(), 'column mode on');

    $view->clear_selection();
    ok(!$view->column_select(), 'column mode off after clear');
    ok(!$view->has_selection(), 'no selection after clear');
};

subtest 'column_selection returns normalized rectangle' => sub {
    my ($doc, $view) = make_view("hello\nworld\nfoo12\nbar34");

    # Anchor at (0, 4), cursor at (2, 1) → top-left is (0,1), bottom-right is (2,4)
    $view->set_cursor(0, 4);
    $view->start_column_selection();
    $view->set_cursor(2, 1, 1);  # extend

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 0, 'top line');
    is($left, 1, 'left col (min of 4 and 1)');
    is($bottom, 2, 'bottom line');
    is($right, 4, 'right col (max of 4 and 1)');
};

subtest 'column_selection normalizes all 4 orderings' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    # Test: anchor bottom-right, cursor top-left
    $view->set_cursor(2, 5);
    $view->start_column_selection();
    $view->set_cursor(0, 1, 1);

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 0, 'top from bottom-right anchor');
    is($left, 1, 'left from bottom-right anchor');
    is($bottom, 2, 'bottom from bottom-right anchor');
    is($right, 5, 'right from bottom-right anchor');

    # Test: anchor top-right, cursor bottom-left
    $view->clear_selection();
    $view->set_cursor(0, 5);
    $view->start_column_selection();
    $view->set_cursor(2, 1, 1);

    ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 0, 'top from top-right anchor');
    is($left, 1, 'left from top-right anchor');
    is($bottom, 2, 'bottom from top-right anchor');
    is($right, 5, 'right from top-right anchor');

    # Test: anchor bottom-left, cursor top-right
    $view->clear_selection();
    $view->set_cursor(2, 1);
    $view->start_column_selection();
    $view->set_cursor(0, 5, 1);

    ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 0, 'top from bottom-left anchor');
    is($left, 1, 'left from bottom-left anchor');
    is($bottom, 2, 'bottom from bottom-left anchor');
    is($right, 5, 'right from bottom-left anchor');
};

subtest 'column_selection returns empty when not in column mode' => sub {
    my ($doc, $view) = make_view("hello\nworld");
    $view->set_cursor(0, 2);
    $view->set_cursor(1, 3, 1);  # linear selection

    my @result = $view->column_selection();
    is(scalar @result, 0, 'no column_selection when not in column mode');
};

subtest 'column_selection returns empty when no selection' => sub {
    my ($doc, $view) = make_view("hello\nworld");
    $view->{column_select} = 1;  # Force mode but no anchor

    my @result = $view->column_selection();
    is(scalar @result, 0, 'no column_selection when no anchor');
};

subtest 'is_column_selected checks rectangle bounds' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr\nstuvwx");

    # Select rectangle: lines 1-2, cols 2-4
    $view->set_cursor(1, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 4, 1);

    # Inside rectangle
    ok($view->is_column_selected(1, 2), 'top-left corner');
    ok($view->is_column_selected(1, 3), 'top edge middle');
    ok($view->is_column_selected(2, 2), 'bottom-left corner');
    ok($view->is_column_selected(2, 3), 'inside');

    # Outside rectangle
    ok(!$view->is_column_selected(0, 3), 'above');
    ok(!$view->is_column_selected(3, 3), 'below');
    ok(!$view->is_column_selected(1, 1), 'left');
    ok(!$view->is_column_selected(1, 4), 'right (exclusive)');
    ok(!$view->is_column_selected(0, 0), 'far outside');
};

subtest 'is_column_selected returns false when not in column mode' => sub {
    my ($doc, $view) = make_view("hello\nworld");
    $view->set_cursor(0, 0);
    $view->set_cursor(1, 3, 1);  # linear selection

    ok(!$view->is_column_selected(0, 1), 'not column selected in linear mode');
};

subtest 'column_selected_text extracts rectangle' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    # Select cols 1-4 on lines 0-2
    $view->set_cursor(0, 1);
    $view->start_column_selection();
    $view->set_cursor(2, 4, 1);

    my $lines = $view->column_selected_text();
    is(ref $lines, 'ARRAY', 'returns arrayref');
    is(scalar @$lines, 3, 'three lines');
    is($lines->[0], 'bcd', 'first line text');
    is($lines->[1], 'hij', 'second line text');
    is($lines->[2], 'nop', 'third line text');
};

subtest 'column_selected_text pads short lines' => sub {
    my ($doc, $view) = make_view("abcdef\ngh\nmnopqr");

    # Select cols 1-5 on all 3 lines — line 1 ("gh") is only 2 chars
    $view->set_cursor(0, 1);
    $view->start_column_selection();
    $view->set_cursor(2, 5, 1);

    my $lines = $view->column_selected_text();
    is(scalar @$lines, 3, 'three lines');
    is($lines->[0], 'bcde', 'full line');
    is($lines->[1], 'h   ', 'short line padded');  # 'h' + 3 spaces
    is($lines->[2], 'nopq', 'full line');
};

subtest 'column_selected_text with very short line' => sub {
    my ($doc, $view) = make_view("abcdef\n\nmnopqr");

    # Select cols 2-5 on all 3 lines — line 1 is empty
    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 5, 1);

    my $lines = $view->column_selected_text();
    is($lines->[0], 'cde', 'first line');
    is($lines->[1], '   ', 'empty line all spaces');
    is($lines->[2], 'opq', 'third line');
};

subtest 'set_cursor allows virtual whitespace in column mode' => sub {
    my ($doc, $view) = make_view("ab\ncd");

    $view->set_cursor(0, 1);
    $view->start_column_selection();

    # Extend to column 10, which is past both lines (len 2)
    $view->set_cursor(1, 10, 1);

    is($view->cursor_col(), 10, 'cursor col beyond line length in column mode');
    ok($view->has_selection(), 'selection still active');
};

subtest 'set_cursor clamps column in normal mode (regression)' => sub {
    my ($doc, $view) = make_view("ab\ncd");

    $view->set_cursor(0, 10);
    is($view->cursor_col(), 2, 'column clamped to line length in normal mode');
};

subtest 'move_up/down in column mode preserves preferred col past line length' => sub {
    my ($doc, $view) = make_view("abcdefghij\nab\nabcdefghij");

    # Start at col 8 on line 0
    $view->set_cursor(0, 8);
    $view->start_column_selection();

    # Move down to line 1 (length 2) — should keep col 8 in column mode
    $view->move_down(1);  # extend selection
    is($view->cursor_line(), 1, 'moved to line 1');
    is($view->cursor_col(), 8, 'column preserved past short line');

    # Move down to line 2 — still col 8
    $view->move_down(1);
    is($view->cursor_line(), 2, 'moved to line 2');
    is($view->cursor_col(), 8, 'column still 8');
};

subtest 'column_edit_ranges returns per-line ranges' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 4, 1);

    my $ranges = $view->column_edit_ranges();
    is(ref $ranges, 'ARRAY', 'returns arrayref');
    is(scalar @$ranges, 3, 'three ranges');

    is($ranges->[0]{line}, 0, 'first range line');
    is($ranges->[0]{start_col}, 2, 'first range start');
    is($ranges->[0]{end_col}, 4, 'first range end');

    is($ranges->[2]{line}, 2, 'last range line');
    is($ranges->[2]{start_col}, 2, 'last range start');
    is($ranges->[2]{end_col}, 4, 'last range end');
};

subtest 'column_edit_ranges empty when not column mode' => sub {
    my ($doc, $view) = make_view("hello");
    my $ranges = $view->column_edit_ranges();
    is(ref $ranges, 'ARRAY', 'returns arrayref');
    is(scalar @$ranges, 0, 'empty when not in column mode');
};

subtest 'Linear selection unchanged by column feature (regression)' => sub {
    my ($doc, $view) = make_view("hello\nworld\ntest");

    # Normal shift+right selection
    $view->move_right(1);
    $view->move_right(1);
    $view->move_right(1);

    ok(!$view->column_select(), 'not in column mode');
    ok($view->has_selection(), 'has linear selection');

    my ($sl, $sc, $el, $ec) = $view->selection();
    is($sl, 0, 'start line');
    is($sc, 0, 'start col');
    is($el, 0, 'end line');
    is($ec, 3, 'end col');
    is($view->selected_text(), 'hel', 'selected text');

    # Move without extend clears
    $view->move_right(0);
    ok(!$view->has_selection(), 'cleared');
    ok(!$view->column_select(), 'still not in column mode');
};

# ============================================================================
# Phase 1.5: Column select via simulated keyboard interaction
# ============================================================================

subtest 'Column select up enters column mode and extends' => sub {
    my ($doc, $view) = make_view("line1\nline2\nline3\nline4");
    $view->set_cursor(2, 3);

    # Simulate do_column_select_up: start column mode, move up with extend
    $view->start_column_selection();
    $view->move_up(1);  # extend

    ok($view->column_select(), 'in column mode');
    ok($view->has_selection(), 'has selection');
    is($view->cursor_line(), 1, 'moved up one line');

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 1, 'top is line 1');
    is($bottom, 2, 'bottom is line 2');
    is($left, 3, 'left col');
    is($right, 3, 'right col (zero-width)');
};

subtest 'Successive column select extends further' => sub {
    my ($doc, $view) = make_view("line1\nline2\nline3\nline4");
    $view->set_cursor(3, 2);

    $view->start_column_selection();
    $view->move_up(1);
    $view->move_up(1);

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 1, 'extended to line 1');
    is($bottom, 3, 'bottom stays at line 3');
};

subtest 'Escape clears column selection' => sub {
    my ($doc, $view) = make_view("line1\nline2\nline3");
    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 4, 1);

    ok($view->column_select(), 'column mode on');
    $view->clear_selection();  # Escape calls this
    ok(!$view->column_select(), 'column mode off');
    ok(!$view->has_selection(), 'no selection');
};

subtest 'Shift+Arrow extends column selection horizontally' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    # Enter column mode at (0, 2), extend down to line 2
    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 2, 1);

    # Now extend right with Shift+Right (extend_selection=1)
    $view->move_right(1);
    $view->move_right(1);

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($left, 2, 'left stays at 2');
    is($right, 4, 'right extended to 4');
    is($top, 0, 'top');
    is($bottom, 2, 'bottom');
};

# ============================================================================
# Phase 2: Rendering Tests
# ============================================================================

# Load rendering dependencies
use Zepto::Renderer;
use Zepto::Theme;
use Zepto::Chars;
use Zepto::Preferences;
use File::Temp qw(tempfile);

sub create_temp_file {
    my ($content) = @_;
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh $content;
    close $fh;
    return $filename;
}

sub strip_escapes {
    my ($str) = @_;
    $str =~ s/\x1b\[[0-9;]*[A-Za-z]//g;
    $str =~ s/\x1b\[\?[0-9]+[hl]//g;
    return $str;
}

sub render_state {
    my ($content, %opts) = @_;
    my $filename = create_temp_file($content);
    my $doc = Zepto::Document->load($filename);
    my $view = Zepto::View->new(
        document => $doc,
        viewport_rows => $opts{rows} // 10,
        viewport_cols => $opts{cols} // 40,
    );
    my $theme = Zepto::Theme->dark_theme();
    return ($doc, $view, $theme);
}

subtest 'Column selection uses column_selection_bg color' => sub {
    my ($doc, $view, $theme) = render_state("abcdef\nghijkl\nmnopqr");

    # Create column selection: lines 0-1, cols 2-4
    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(1, 4, 1);

    my $output = Zepto::Renderer->render(
        document => $doc, view => $view, theme => $theme,
        rows => 10, cols => 40,
    );

    # Should contain column_selection_bg color (RGB 60,55,120)
    like($output, qr/\x1b\[48;2;60;55;120m/, 'Contains column selection bg color');
};

subtest 'Linear selection still uses selection_bg (regression)' => sub {
    my ($doc, $view, $theme) = render_state("abcdef\nghijkl\nmnopqr");

    # Create linear selection
    $view->set_cursor(0, 2);
    $view->set_cursor(0, 4, 1);

    ok(!$view->column_select(), 'linear selection, not column');

    my $output = Zepto::Renderer->render(
        document => $doc, view => $view, theme => $theme,
        rows => 10, cols => 40,
    );

    # Should contain selection_bg color (RGB 51,70,124)
    like($output, qr/\x1b\[48;2;51;70;124m/, 'Contains linear selection bg color');
    # Should NOT contain column selection color
    unlike($output, qr/\x1b\[48;2;60;55;120m/, 'Does not contain column selection bg');
};

subtest 'Zero-width column cursor uses column_cursor_bg' => sub {
    my ($doc, $view, $theme) = render_state("abcdef\nghijkl\nmnopqr");

    # Create zero-width column selection at col 3, lines 0-2
    $view->set_cursor(0, 3);
    $view->start_column_selection();
    $view->set_cursor(2, 3, 1);

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($left, 3, 'zero width: left == right');
    is($right, 3, 'zero width confirmed');

    my $output = Zepto::Renderer->render(
        document => $doc, view => $view, theme => $theme,
        rows => 10, cols => 40,
    );

    # Should contain column_cursor_bg color (RGB 80,70,150)
    like($output, qr/\x1b\[48;2;80;70;150m/, 'Contains column cursor bg color');
};

subtest 'Column selection fill area shows virtual whitespace' => sub {
    my ($doc, $view, $theme) = render_state("abcdef\ngh\nmnopqr");

    # Select cols 1-5 on all lines — line 1 ("gh") is only 2 chars
    # The fill area of line 1 should show column selection highlight
    $view->set_cursor(0, 1);
    $view->start_column_selection();
    $view->set_cursor(2, 5, 1);

    my $output = Zepto::Renderer->render(
        document => $doc, view => $view, theme => $theme,
        rows => 10, cols => 40,
    );

    # The column selection bg should appear (both in content area and fill area)
    my @col_sel_matches = ($output =~ /\x1b\[48;2;60;55;120m/g);
    ok(scalar @col_sel_matches >= 2, 'Column selection bg appears on multiple lines (including fill)');
};

# ============================================================================
# Phase 4: Multi-Line Editing Operations
# ============================================================================

# Helper to simulate the editor's column operations on a doc+view
# (We test the building blocks here; full editor integration is in editor.t)

subtest 'Column delete: remove rectangle content' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    # Select cols 2-4 on lines 0-2
    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 4, 1);

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 0, 'top');
    is($left, 2, 'left');
    is($bottom, 2, 'bottom');
    is($right, 4, 'right');

    # Delete bottom-to-top (simulating column delete)
    for my $ln (reverse $top .. $bottom) {
        my $line_len = $doc->line_length($ln);
        next if $line_len <= $left;
        my $del_end = $right < $line_len ? $right : $line_len;
        my $del_len = $del_end - $left;
        next if $del_len <= 0;
        my $offset = $doc->line_col_to_offset($ln, $left);
        $doc->delete($offset, $del_len);
    }

    is($doc->get_line_content(0), 'abef', 'line 0 after column delete');
    is($doc->get_line_content(1), 'ghkl', 'line 1 after column delete');
    is($doc->get_line_content(2), 'mnqr', 'line 2 after column delete');
};

subtest 'Column insert: insert char on each line' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    # Create zero-width column cursor at col 2, lines 0-2
    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 2, 1);

    my ($top, $left, $bottom, $right) = $view->column_selection();

    # Insert 'X' at col 2 on each line, bottom-to-top
    for my $ln (reverse $top .. $bottom) {
        my $offset = $doc->line_col_to_offset($ln, $left);
        $doc->insert($offset, 'X');
    }

    is($doc->get_line_content(0), 'abXcdef', 'line 0 after column insert');
    is($doc->get_line_content(1), 'ghXijkl', 'line 1 after column insert');
    is($doc->get_line_content(2), 'mnXopqr', 'line 2 after column insert');
};

subtest 'Column insert with virtual whitespace padding' => sub {
    my ($doc, $view) = make_view("abcdef\ngh\nmnopqr");

    # Create zero-width column cursor at col 5, lines 0-2
    # Line 1 ("gh") is only 2 chars, needs padding
    $view->set_cursor(0, 5);
    $view->start_column_selection();
    $view->set_cursor(2, 5, 1);

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($left, 5, 'col 5');

    # Insert 'X' at col 5, padding short lines, bottom-to-top
    for my $ln (reverse $top .. $bottom) {
        my $line_len = $doc->line_length($ln);
        if ($line_len < $left) {
            my $pad = ' ' x ($left - $line_len);
            my $offset = $doc->line_col_to_offset($ln, $line_len);
            $doc->insert($offset, $pad);
        }
        my $offset = $doc->line_col_to_offset($ln, $left);
        $doc->insert($offset, 'X');
    }

    is($doc->get_line_content(0), 'abcdeXf', 'long line: inserted at col 5');
    is($doc->get_line_content(1), 'gh   X', 'short line: padded then inserted');
    is($doc->get_line_content(2), 'mnopqXr', 'long line: inserted at col 5');
};

subtest 'Column replace: delete rectangle then insert char' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    # Select cols 1-4 on lines 0-2
    $view->set_cursor(0, 1);
    $view->start_column_selection();
    $view->set_cursor(2, 4, 1);

    my ($top, $left, $bottom, $right) = $view->column_selection();

    # Delete selection then insert 'X', bottom-to-top
    for my $ln (reverse $top .. $bottom) {
        my $line_len = $doc->line_length($ln);
        my $del_end = $right < $line_len ? $right : $line_len;
        my $del_len = $del_end - $left;
        my $offset = $doc->line_col_to_offset($ln, $left);
        $doc->delete($offset, $del_len) if $del_len > 0;
        $doc->insert($offset, 'X');
    }

    is($doc->get_line_content(0), 'aXef', 'line 0: replaced bcd with X');
    is($doc->get_line_content(1), 'gXkl', 'line 1: replaced hij with X');
    is($doc->get_line_content(2), 'mXqr', 'line 2: replaced nop with X');
};

subtest 'Column backspace at zero-width cursor' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    # Zero-width at col 3, lines 0-2
    $view->set_cursor(0, 3);
    $view->start_column_selection();
    $view->set_cursor(2, 3, 1);

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($left, 3, 'cursor at col 3');
    is($right, 3, 'zero width');

    # Backspace: delete char before col 3 on each line, bottom-to-top
    for my $ln (reverse $top .. $bottom) {
        my $line_len = $doc->line_length($ln);
        next if $line_len < $left;
        my $offset = $doc->line_col_to_offset($ln, $left - 1);
        $doc->delete($offset, 1);
    }

    is($doc->get_line_content(0), 'abdef', 'line 0: c (col 2) deleted');
    is($doc->get_line_content(1), 'ghjkl', 'line 1: i (col 2) deleted');
    is($doc->get_line_content(2), 'mnpqr', 'line 2: o (col 2) deleted');
};

subtest 'Column copy produces rectangular text' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 4, 1);

    my $lines = $view->column_selected_text();
    my $clipboard = join("\n", @$lines);
    is($clipboard, "cd\nij\nop", 'columnar clipboard text');
};

subtest 'Columnar paste distributes lines' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr");

    # Paste 3 lines at col 2, starting at line 0
    my @paste_lines = ('XX', 'YY', 'ZZ');
    my $start_line = 0;
    my $start_col = 2;

    # Insert bottom-to-top
    for my $i (reverse 0 .. $#paste_lines) {
        my $target_line = $start_line + $i;
        my $offset = $doc->line_col_to_offset($target_line, $start_col);
        $doc->insert($offset, $paste_lines[$i]);
    }

    is($doc->get_line_content(0), 'abXXcdef', 'line 0: XX inserted at col 2');
    is($doc->get_line_content(1), 'ghYYijkl', 'line 1: YY inserted at col 2');
    is($doc->get_line_content(2), 'mnZZopqr', 'line 2: ZZ inserted at col 2');
};

subtest 'Undo reverts column insert (multiple undos for non-adjacent edits)' => sub {
    my ($doc, $view) = make_view("abc\ndef\nghi");

    $doc->break_undo_group();

    # Insert 'X' at col 1 on all lines, bottom-to-top
    for my $ln (reverse 0 .. 2) {
        my $offset = $doc->line_col_to_offset($ln, 1);
        $doc->insert($offset, 'X');
    }

    $doc->break_undo_group();

    is($doc->get_line_content(0), 'aXbc', 'after insert');
    is($doc->get_line_content(1), 'dXef', 'after insert');
    is($doc->get_line_content(2), 'gXhi', 'after insert');

    # Undo all column edits (may require multiple undo calls since
    # edits on different lines have non-adjacent offsets)
    while ($doc->can_undo()) {
        $doc->undo();
    }
    is($doc->get_line_content(0), 'abc', 'undo line 0');
    is($doc->get_line_content(1), 'def', 'undo line 1');
    is($doc->get_line_content(2), 'ghi', 'undo line 2');
};

# ============================================================================
# Virtual whitespace: selection extends past short line ends
# ============================================================================

subtest 'Column selection rectangle preserves virtual columns past short lines' => sub {
    # Lines: "abcdefghij" (10), "abc" (3), "abcdefghij" (10)
    # Start at line 0, col 5; extend down to line 2
    # Rectangle should be 3 lines at col 5, even though line 1 is only 3 chars
    my ($doc, $view) = make_view("abcdefghij\nabc\nabcdefghij");

    $view->set_cursor(0, 5);
    $view->start_column_selection();
    $view->set_cursor(2, 5, 1);

    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($top, 0, 'top line');
    is($left, 5, 'left col preserved at 5');
    is($bottom, 2, 'bottom line');
    is($right, 5, 'right col preserved at 5 (zero-width)');

    # Extend selection right to col 8
    $view->set_cursor(2, 8, 1);
    ($top, $left, $bottom, $right) = $view->column_selection();
    is($left, 5, 'left col still 5');
    is($right, 8, 'right col extended to 8');

    # column_selected_text should space-pad line 1
    my $texts = $view->column_selected_text();
    is($texts->[0], 'fgh', 'line 0: real chars');
    is($texts->[1], '   ', 'line 1: all spaces (virtual whitespace)');
    is($texts->[2], 'fgh', 'line 2: real chars');
};

subtest 'Column selection rendering extends past short line in fill area' => sub {
    # "abcdefghij" (10), "ab" (2), "abcdefghij" (10)
    # Select cols 4-7 across all three lines
    my ($doc, $view, $theme) = render_state("abcdefghij\nab\nabcdefghij");

    $view->set_cursor(0, 4);
    $view->start_column_selection();
    $view->set_cursor(2, 7, 1);

    my $output = Zepto::Renderer->render(
        document => $doc, view => $view, theme => $theme,
        rows => 10, cols => 40,
    );

    # Column selection bg (RGB 60,55,120) should appear at least 3 times
    # (once per line — line 1 should show it in the fill area)
    my @col_sel = ($output =~ /\x1b\[48;2;60;55;120m/g);
    ok(scalar @col_sel >= 3, "Column selection bg on all 3 lines (got " . scalar(@col_sel) . ")");
};

subtest 'Alt+Click sets cursor with virtual whitespace in column mode' => sub {
    # Verify that set_cursor in column mode allows col past line end
    my ($doc, $view) = make_view("abcdefghij\nab\nabcdefghij");

    # Simulate: position on long line, start column select, extend to short line
    $view->set_cursor(0, 7);
    $view->start_column_selection();
    # Now extend to line 1 (only 2 chars) at col 7 — should NOT clamp to 2
    $view->set_cursor(1, 7, 1);

    is($view->cursor_col(), 7, 'cursor col stays at 7 past short line end');
    my ($top, $left, $bottom, $right) = $view->column_selection();
    is($left, 7, 'selection left is 7');
    is($right, 7, 'selection right is 7 (zero-width at col 7)');
};

# ============================================================================
# Phase 5: Polish & Discoverability
# ============================================================================

subtest 'Status bar shows COL indicator with dimensions' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr\nstuvwx", rows => 10, cols => 60);

    # Select a 3-line × 2-col rectangle: lines 0-2, cols 1-3
    $view->set_cursor(0, 1);
    $view->start_column_selection();
    $view->set_cursor(2, 3, 1);

    my $theme = Zepto::Theme->get_theme('dark');
    my $output = Zepto::Renderer->_render_status_bar($doc, $view, $theme, 60, undef, undef, undef);
    # Should contain "COL 3×2" (3 lines, 2 cols)
    like($output, qr/COL 3\x{00D7}2/, 'status bar shows COL LINESxCOLS for width > 0');

    # Zero-width column (cursor bar)
    $view->set_cursor(0, 2);
    $view->start_column_selection();
    $view->set_cursor(2, 2, 1);

    $output = Zepto::Renderer->_render_status_bar($doc, $view, $theme, 60, undef, undef, undef);
    like($output, qr/COL 3 lines/, 'status bar shows COL N lines for zero-width');
};

subtest 'Status bar has no COL indicator without column selection' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl", rows => 10, cols => 60);

    my $theme = Zepto::Theme->get_theme('dark');
    my $output = Zepto::Renderer->_render_status_bar($doc, $view, $theme, 60, undef, undef, undef);
    unlike($output, qr/COL/, 'no COL indicator without column selection');
};

subtest 'Column indicator theme colors exist' => sub {
    my $dark = Zepto::Theme->get_theme('dark');
    ok($dark->color('column_indicator_fg'), 'dark theme has column_indicator_fg');
    ok($dark->color('column_indicator_bg'), 'dark theme has column_indicator_bg');
    ok($dark->color('column_indicator_edge'), 'dark theme has column_indicator_edge');

    my $light = Zepto::Theme->get_theme('light');
    ok($light->color('column_indicator_fg'), 'light theme has column_indicator_fg');
    ok($light->color('column_indicator_bg'), 'light theme has column_indicator_bg');
    ok($light->color('column_indicator_edge'), 'light theme has column_indicator_edge');
};

subtest 'Find mode clears column selection' => sub {
    my ($doc, $view) = make_view("abcdef\nghijkl\nmnopqr", rows => 10, cols => 40);

    $view->set_cursor(0, 1);
    $view->start_column_selection();
    $view->set_cursor(2, 3, 1);
    ok($view->column_select(), 'column select active before find');

    # Simulate what enter_find_mode does to the view
    # (We can't easily call Editor::enter_find_mode without full editor setup,
    #  so test the View-level behavior directly)
    $view->clear_selection();
    ok(!$view->column_select(), 'column select cleared (as enter_find_mode would do)');
    ok(!$view->has_selection(), 'selection also cleared');
};

done_testing();
