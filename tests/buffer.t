#!/usr/bin/env perl
# Comprehensive tests for Zepto::Buffer (gap buffer implementation)
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Zepto::Buffer;

# ============================================================================
# Construction tests
# ============================================================================
subtest 'Construction' => sub {
    my $buf = Zepto::Buffer->new();
    is($buf->text(), '', 'Empty buffer has empty text');
    is($buf->length(), 0, 'Empty buffer has zero length');
    is($buf->line_count(), 1, 'Empty buffer has one line');

    $buf = Zepto::Buffer->new('hello');
    is($buf->text(), 'hello', 'Buffer initialized with text');
    is($buf->length(), 5, 'Buffer has correct length');

    $buf = Zepto::Buffer->new("line1\nline2\n");
    is($buf->line_count(), 3, 'Buffer with newlines has correct line count');
};

# ============================================================================
# Insert tests
# ============================================================================
subtest 'Insert operations' => sub {
    my $buf = Zepto::Buffer->new();

    # Insert at start
    $buf->insert(0, 'hello');
    is($buf->text(), 'hello', 'Insert at start');

    # Insert at end
    $buf->insert(5, ' world');
    is($buf->text(), 'hello world', 'Insert at end');

    # Insert in middle
    $buf->insert(5, ',');
    is($buf->text(), 'hello, world', 'Insert in middle');

    # Insert empty string (no-op)
    $buf->insert(0, '');
    is($buf->text(), 'hello, world', 'Insert empty string is no-op');

    # Insert at position 0 of non-empty buffer
    $buf = Zepto::Buffer->new('world');
    $buf->insert(0, 'hello ');
    is($buf->text(), 'hello world', 'Insert at position 0 of non-empty buffer');
};

subtest 'Insert with newlines' => sub {
    my $buf = Zepto::Buffer->new();
    $buf->insert(0, "line1\nline2");
    is($buf->line_count(), 2, 'Insert creates correct line count');
    is($buf->get_line_content(0), 'line1', 'First line correct');
    is($buf->get_line_content(1), 'line2', 'Second line correct');

    $buf->insert(5, "\ninserted\n");
    is($buf->text(), "line1\ninserted\n\nline2", 'Insert with newlines');
    is($buf->line_count(), 4, 'Line count updated after insert');
};

# ============================================================================
# Delete tests
# ============================================================================
subtest 'Delete operations' => sub {
    my $buf = Zepto::Buffer->new('hello world');

    # Delete from middle
    my $deleted = $buf->delete(5, 1);
    is($deleted, ' ', 'Delete returns deleted text');
    is($buf->text(), 'helloworld', 'Delete from middle');

    # Delete from start
    $deleted = $buf->delete(0, 5);
    is($deleted, 'hello', 'Delete from start returns text');
    is($buf->text(), 'world', 'Delete from start');

    # Delete from end
    $buf = Zepto::Buffer->new('hello');
    $deleted = $buf->delete(3, 2);
    is($deleted, 'lo', 'Delete from end');
    is($buf->text(), 'hel', 'Text after delete from end');

    # Delete more than available
    $buf = Zepto::Buffer->new('hi');
    $deleted = $buf->delete(0, 100);
    is($deleted, 'hi', 'Delete clamps to available');
    is($buf->text(), '', 'Buffer empty after over-delete');

    # Delete with zero length
    $buf = Zepto::Buffer->new('hello');
    $deleted = $buf->delete(0, 0);
    is($deleted, '', 'Delete with zero length');
    is($buf->text(), 'hello', 'Buffer unchanged');
};

subtest 'Delete with newlines' => sub {
    my $buf = Zepto::Buffer->new("line1\nline2\nline3");
    $buf->delete(5, 1);  # Delete first newline
    is($buf->text(), "line1line2\nline3", 'Delete newline joins lines');
    is($buf->line_count(), 2, 'Line count reduced');
};

# ============================================================================
# Get text tests
# ============================================================================
subtest 'Get text operations' => sub {
    my $buf = Zepto::Buffer->new('hello world');

    is($buf->get_text(0, 5), 'hello', 'Get text from start');
    is($buf->get_text(6, 11), 'world', 'Get text from middle');
    is($buf->get_text(0, 11), 'hello world', 'Get all text');
    is($buf->get_text(), 'hello world', 'Get text with defaults');
    is($buf->get_text(5, 5), '', 'Get empty range');
    is($buf->get_text(0, 100), 'hello world', 'Get text clamps to length');
};

# ============================================================================
# Line operations tests
# ============================================================================
subtest 'Line operations' => sub {
    my $buf = Zepto::Buffer->new("first\nsecond\nthird");

    is($buf->line_count(), 3, 'Correct line count');
    is($buf->get_line(0), "first\n", 'Get first line (includes newline)');
    is($buf->get_line(1), "second\n", 'Get second line');
    is($buf->get_line(2), 'third', 'Get last line (no trailing newline)');
    is($buf->get_line(99), '', 'Get out of bounds line');
    is($buf->get_line(-1), '', 'Get negative line');

    is($buf->get_line_content(0), 'first', 'Get line content strips newline');
    is($buf->get_line_content(2), 'third', 'Get last line content');

    is($buf->line_length(0), 5, 'Line length excludes newline');
    is($buf->line_length(1), 6, 'Line length correct');
};

subtest 'Line with CRLF' => sub {
    my $buf = Zepto::Buffer->new("line1\r\nline2\r\n");
    is($buf->get_line_content(0), 'line1', 'CRLF line content strips both');
    is($buf->get_line_content(1), 'line2', 'Second CRLF line');
};

subtest 'Line start offsets' => sub {
    my $buf = Zepto::Buffer->new("ab\ncd\nef");
    is($buf->line_start_offset(0), 0, 'First line starts at 0');
    is($buf->line_start_offset(1), 3, 'Second line offset');
    is($buf->line_start_offset(2), 6, 'Third line offset');
};

# ============================================================================
# Coordinate conversion tests
# ============================================================================
subtest 'Offset to line/col conversion' => sub {
    my $buf = Zepto::Buffer->new("hello\nworld\n!");

    my ($line, $col) = $buf->offset_to_line_col(0);
    is($line, 0, 'Offset 0: line 0');
    is($col, 0, 'Offset 0: col 0');

    ($line, $col) = $buf->offset_to_line_col(3);
    is($line, 0, 'Offset 3: line 0');
    is($col, 3, 'Offset 3: col 3');

    ($line, $col) = $buf->offset_to_line_col(6);
    is($line, 1, 'Offset 6: line 1');
    is($col, 0, 'Offset 6: col 0');

    ($line, $col) = $buf->offset_to_line_col(12);
    is($line, 2, 'Offset 12: line 2');
    is($col, 0, 'Offset 12: col 0');
};

subtest 'Line/col to offset conversion' => sub {
    my $buf = Zepto::Buffer->new("hello\nworld\n!");

    is($buf->line_col_to_offset(0, 0), 0, 'Line 0, col 0 -> offset 0');
    is($buf->line_col_to_offset(0, 3), 3, 'Line 0, col 3 -> offset 3');
    is($buf->line_col_to_offset(1, 0), 6, 'Line 1, col 0 -> offset 6');
    is($buf->line_col_to_offset(1, 5), 11, 'Line 1, col 5 -> offset 11');
    is($buf->line_col_to_offset(2, 0), 12, 'Line 2, col 0 -> offset 12');

    # Clamping
    is($buf->line_col_to_offset(0, 100), 5, 'Column clamped to line length');
    is($buf->line_col_to_offset(-1, 0), 0, 'Negative line clamped');
    is($buf->line_col_to_offset(100, 0), 12, 'Line beyond end clamped');
};

# ============================================================================
# Replace tests
# ============================================================================
subtest 'Replace operations' => sub {
    my $buf = Zepto::Buffer->new('hello world');

    my $deleted = $buf->replace(0, 5, 'hi');
    is($deleted, 'hello', 'Replace returns deleted text');
    is($buf->text(), 'hi world', 'Replace at start');

    $buf = Zepto::Buffer->new('hello world');
    $buf->replace(6, 11, 'there');
    is($buf->text(), 'hello there', 'Replace at end');

    $buf = Zepto::Buffer->new('hello world');
    $buf->replace(5, 6, ' beautiful ');
    is($buf->text(), 'hello beautiful world', 'Replace in middle');
};

# ============================================================================
# Gap movement stress tests
# ============================================================================
subtest 'Gap movement patterns' => sub {
    my $buf = Zepto::Buffer->new('0123456789');

    # Insert at various positions, forcing gap movement
    $buf->insert(5, 'A');   # Middle
    is($buf->text(), '01234A56789', 'Insert at 5');

    $buf->insert(0, 'B');   # Start (gap moves left)
    is($buf->text(), 'B01234A56789', 'Insert at 0');

    $buf->insert(12, 'C');  # End (gap moves right)
    is($buf->text(), 'B01234A56789C', 'Insert at end');

    $buf->insert(3, 'D');   # Back to middle
    is($buf->text(), 'B01D234A56789C', 'Insert at 3');
};

subtest 'Alternating operations' => sub {
    my $buf = Zepto::Buffer->new('');

    # Build up text with alternating positions
    $buf->insert(0, 'A');
    $buf->insert(0, 'B');
    $buf->insert(1, 'C');
    $buf->insert(3, 'D');
    is($buf->text(), 'BCAD', 'Alternating inserts');

    $buf->delete(1, 1);  # Remove C
    is($buf->text(), 'BAD', 'Delete from middle');

    $buf->delete(0, 1);  # Remove B
    is($buf->text(), 'AD', 'Delete from start');
};

# ============================================================================
# Edge cases
# ============================================================================
subtest 'Edge cases' => sub {
    # Empty buffer operations
    my $buf = Zepto::Buffer->new('');
    is($buf->get_line(0), '', 'Empty buffer get_line');
    is($buf->get_line_content(0), '', 'Empty buffer get_line_content');

    # Single character
    $buf = Zepto::Buffer->new('x');
    is($buf->line_count(), 1, 'Single char is one line');
    is($buf->get_line_content(0), 'x', 'Single char content');

    # Only newlines
    $buf = Zepto::Buffer->new("\n\n\n");
    is($buf->line_count(), 4, 'Three newlines = four lines');
    is($buf->get_line_content(0), '', 'First empty line');
    is($buf->get_line_content(3), '', 'Last empty line');

    # Trailing newline
    $buf = Zepto::Buffer->new("hello\n");
    is($buf->line_count(), 2, 'Trailing newline adds empty line');
    is($buf->get_line_content(1), '', 'Empty last line');
};

# ============================================================================
# Unicode tests
# ============================================================================
subtest 'Unicode handling' => sub {
    my $buf = Zepto::Buffer->new('');
    $buf->insert(0, '日本語');
    is($buf->text(), '日本語', 'Unicode insert');

    $buf = Zepto::Buffer->new('αβγ');
    is($buf->length(), 3, 'Greek letters character length');

    $buf = Zepto::Buffer->new("emoji: 🎉");
    like($buf->text(), qr/🎉/, 'Emoji preserved');

    # Unicode line operations
    $buf = Zepto::Buffer->new("日本語\n中文");
    is($buf->line_count(), 2, 'Unicode lines counted');
    is($buf->get_line_content(0), '日本語', 'First unicode line');
    is($buf->get_line_content(1), '中文', 'Second unicode line');
};

# ============================================================================
# Performance sanity checks (not real benchmarks, just sanity)
# ============================================================================
subtest 'Performance sanity' => sub {
    my $buf = Zepto::Buffer->new('');

    # Many small inserts at cursor position (should be O(1) each)
    for my $i (1..1000) {
        $buf->insert($buf->length(), 'x');
    }
    is($buf->length(), 1000, '1000 inserts at end');

    # Many small inserts at start (forces gap movement each time)
    $buf = Zepto::Buffer->new('');
    for my $i (1..100) {
        $buf->insert(0, 'y');
    }
    is($buf->length(), 100, '100 inserts at start');
    is(substr($buf->text(), 0, 1), 'y', 'First char is y');
};

done_testing();
