package Zepto::Buffer;
# =============================================================================
# Gap Buffer Implementation for Efficient Text Editing
# =============================================================================
#
# A gap buffer is a data structure that allows efficient insertion and deletion
# at the cursor position. It maintains a "gap" (unused space) at the cursor
# position, so edits there are O(1). Moving the cursor moves the gap, which is
# O(n), but amortized O(1) for typical editing patterns.
#
# =============================================================================
# HOW IT WORKS
# =============================================================================
#
# Conceptually, the buffer looks like this:
#
#   +------------------------------------------+
#   | TEXT BEFORE CURSOR |  GAP  | TEXT AFTER  |
#   +------------------------------------------+
#                        ^
#                     cursor
#
# Example: The text "Hello World" with cursor after "Hello ":
#
#   +---+---+---+---+---+---+~~~~~+---+---+---+---+---+
#   | H | e | l | l | o |   | GAP | W | o | r | l | d |
#   +---+---+---+---+---+---+~~~~~+---+---+---+---+---+
#                          ^
#                       cursor
#
# INSERTION: When inserting at cursor, we simply add to pre_gap. O(1).
#
#   Before: pre_gap="Hello " | post_gap="World"
#   Insert "Beautiful "
#   After:  pre_gap="Hello Beautiful " | post_gap="World"
#
# DELETION: When deleting at cursor, we remove from post_gap. O(1).
#
#   Before: pre_gap="Hello " | post_gap="World"
#   Delete 5 chars
#   After:  pre_gap="Hello " | post_gap=""
#
# CURSOR MOVEMENT: Moving the cursor moves text between pre_gap and post_gap.
#
#   Move cursor left by 3:
#   Before: pre_gap="Hello " | post_gap="World"
#   After:  pre_gap="Hel"    | post_gap="lo World"
#
# =============================================================================
# IMPLEMENTATION NOTES
# =============================================================================
#
# We represent the buffer as two strings:
#   - pre_gap:  text before the cursor (grows when inserting)
#   - post_gap: text after the cursor (shrinks when deleting)
#
# This is simpler than using an array with an actual gap. The "gap" is implicit
# - it's the space between the end of pre_gap and start of post_gap.
#
# Line Index:
#   For efficient line operations, we maintain an index of line start offsets.
#   This is rebuilt lazily when line_count() or get_line() is called after edits.
#
# =============================================================================

use strict;
use warnings;
use utf8;

# Create a new buffer, optionally initialized with text
# The cursor starts at position 0 (all text is in post_gap)
sub new {
    my ($class, $text) = @_;
    $text //= '';

    my $self = bless {
        pre_gap  => '',      # Text before cursor
        post_gap => '',      # Text after cursor
        _line_index => undef,
        _line_index_valid => 0,
    }, $class;

    # Initialize: cursor at start, all text after cursor
    $self->{post_gap} = $text;

    return $self;
}

# -----------------------------------------------------------------------------
# Core Operations
# -----------------------------------------------------------------------------

# Move the gap to the specified position
#
# Example: gap at position 6, move to position 3
#
#   Before: pre_gap="Hello " | post_gap="World"
#           Position: 0123456
#                           ^gap at 6
#
#   After:  pre_gap="Hel" | post_gap="lo World"
#           Position: 012
#                        ^gap at 3
#
sub _move_gap_to {
    my ($self, $pos) = @_;

    my $pre_len = CORE::length($self->{pre_gap});

    if ($pos < $pre_len) {
        # Move gap left: transfer from pre_gap to post_gap
        my $move = substr($self->{pre_gap}, $pos);
        $self->{pre_gap} = substr($self->{pre_gap}, 0, $pos);
        $self->{post_gap} = $move . $self->{post_gap};
    }
    elsif ($pos > $pre_len) {
        # Move gap right: transfer from post_gap to pre_gap
        my $move_len = $pos - $pre_len;
        my $move = substr($self->{post_gap}, 0, $move_len);
        $self->{pre_gap} .= $move;
        $self->{post_gap} = substr($self->{post_gap}, $move_len);
    }
    # If $pos == $pre_len, gap is already there
}

# Insert text at the specified position
# Returns the number of characters inserted
sub insert {
    my ($self, $pos, $text) = @_;
    return if !defined($text) || $text eq '';

    $self->_move_gap_to($pos);
    $self->{pre_gap} .= $text;
    $self->{_line_index_valid} = 0;

    return CORE::length($text);
}

# Delete `len` characters starting at position `pos`
# Returns the deleted text
sub delete {
    my ($self, $pos, $len) = @_;
    return '' if !defined($len) || $len <= 0;

    $self->_move_gap_to($pos);

    # Delete from post_gap (text after cursor position)
    my $available = CORE::length($self->{post_gap});
    my $actual_len = $len > $available ? $available : $len;

    my $deleted = substr($self->{post_gap}, 0, $actual_len);
    $self->{post_gap} = substr($self->{post_gap}, $actual_len);
    $self->{_line_index_valid} = 0;

    return $deleted;
}

# Get text from byte position `start` to `end`
sub get_text {
    my ($self, $start, $end) = @_;
    $start //= 0;
    $end //= $self->length();

    return '' if $start >= $end;

    my $full = $self->{pre_gap} . $self->{post_gap};
    my $len = $end - $start;
    $len = CORE::length($full) - $start if $start + $len > CORE::length($full);

    return substr($full, $start, $len);
}

# Get the full text content
sub text {
    my ($self) = @_;
    return $self->{pre_gap} . $self->{post_gap};
}

# Get total length in characters
sub length {
    my ($self) = @_;
    return CORE::length($self->{pre_gap}) + CORE::length($self->{post_gap});
}

# Replace a range of text (delete then insert)
sub replace {
    my ($self, $start, $end, $text) = @_;
    my $deleted = $self->delete($start, $end - $start);
    $self->insert($start, $text);
    return $deleted;
}

# -----------------------------------------------------------------------------
# Line Operations
# -----------------------------------------------------------------------------

# Rebuild the line index
# The index is an array of [start_offset, length] for each line
#
# Example: "Hello\nWorld\n"
#   Line 0: start=0, length=6 ("Hello\n")
#   Line 1: start=6, length=6 ("World\n")
#   Line 2: start=12, length=0 (empty line after final newline)
#
sub _ensure_line_index {
    my ($self) = @_;
    return if $self->{_line_index_valid};

    my $text = $self->text();
    my @lines;
    my $pos = 0;

    while ($pos <= CORE::length($text)) {
        my $newline_pos = index($text, "\n", $pos);
        if ($newline_pos == -1) {
            # Last line (no trailing newline)
            push @lines, [$pos, CORE::length($text) - $pos];
            last;
        }
        else {
            # Line including the newline character
            push @lines, [$pos, $newline_pos - $pos + 1];
            $pos = $newline_pos + 1;
        }
    }

    # Handle empty buffer
    if (@lines == 0) {
        @lines = ([0, 0]);
    }

    $self->{_line_index} = \@lines;
    $self->{_line_index_valid} = 1;
}

# Get number of lines in the buffer
sub line_count {
    my ($self) = @_;
    $self->_ensure_line_index();
    return scalar @{$self->{_line_index}};
}

# Get a specific line (0-indexed), including newline if present
sub get_line {
    my ($self, $line_num) = @_;
    $self->_ensure_line_index();

    return '' if $line_num < 0 || $line_num >= @{$self->{_line_index}};

    my ($start, $len) = @{$self->{_line_index}[$line_num]};
    return $self->get_text($start, $start + $len);
}

# Get line content without trailing newline
sub get_line_content {
    my ($self, $line_num) = @_;
    my $line = $self->get_line($line_num);
    $line =~ s/\r?\n$//;
    return $line;
}

# Get the byte offset of the start of a line
sub line_start_offset {
    my ($self, $line_num) = @_;
    $self->_ensure_line_index();

    return 0 if $line_num < 0;
    return $self->length() if $line_num >= @{$self->{_line_index}};

    return $self->{_line_index}[$line_num][0];
}

# Get the length of a line (excluding newline)
sub line_length {
    my ($self, $line_num) = @_;
    return CORE::length($self->get_line_content($line_num));
}

# -----------------------------------------------------------------------------
# Coordinate Conversion
# -----------------------------------------------------------------------------

# Convert byte offset to (line, column), both 0-indexed
#
# Example: "Hello\nWorld" with offset 8
#   offset 8 is 'r' in "World"
#   Returns (1, 2) - line 1, column 2
#
sub offset_to_line_col {
    my ($self, $offset) = @_;
    $self->_ensure_line_index();

    $offset = 0 if $offset < 0;
    my $len = $self->length();
    $offset = $len if $offset > $len;

    my $index = $self->{_line_index};
    my $num_lines = scalar @$index;
    return (0, 0) unless $num_lines;

    # Binary search for the line containing offset
    my ($lo, $hi) = (0, $num_lines - 1);
    while ($lo < $hi) {
        my $mid = int(($lo + $hi + 1) / 2);
        if ($index->[$mid][0] <= $offset) {
            $lo = $mid;
        } else {
            $hi = $mid - 1;
        }
    }

    my ($start, $line_len) = @{$index->[$lo]};
    return ($lo, $offset - $start);
}

# Convert (line, column) to byte offset, both 0-indexed
# Column is clamped to line length
sub line_col_to_offset {
    my ($self, $line, $col) = @_;
    $self->_ensure_line_index();

    $line = 0 if $line < 0;
    $line = $#{$self->{_line_index}} if $line > $#{$self->{_line_index}};

    my ($start, $len) = @{$self->{_line_index}[$line]};

    # Clamp column to line length (excluding newline)
    my $line_content = $self->get_line_content($line);
    my $max_col = CORE::length($line_content);
    $col = 0 if $col < 0;
    $col = $max_col if $col > $max_col;

    return $start + $col;
}

1;
