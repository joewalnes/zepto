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
    $self->_update_line_index_on_insert($pos, $text);

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
    $self->_update_line_index_on_delete($pos, $deleted);

    return $deleted;
}

# Get text from character position `start` to `end`
#
# PERFORMANCE: reads the requested slice directly out of pre_gap/post_gap
# instead of concatenating the whole document first. Three cases:
#   - range entirely within pre_gap  -> substr(pre_gap, ...)   (no concat)
#   - range entirely within post_gap -> substr(post_gap, ...)  (no concat)
#   - range straddles the gap        -> concat only the two small slices
#     that fall within [start, end), never the full document.
# This matters because get_line()/get_line_content() (called ~40-80x per
# rendered frame, once per visible row) go through this function -- with
# the old "concat pre_gap+post_gap unconditionally" implementation, every
# single-line read re-copied the ENTIRE document.
sub get_text {
    my ($self, $start, $end) = @_;
    $start //= 0;
    $end //= $self->length();

    return '' if $start >= $end;

    my $len = $self->length();
    $end = $len if $end > $len;
    $start = 0 if $start < 0;
    return '' if $start >= $end;

    my $pre_len = CORE::length($self->{pre_gap});

    if ($end <= $pre_len) {
        # Entirely within pre_gap.
        return substr($self->{pre_gap}, $start, $end - $start);
    }
    elsif ($start >= $pre_len) {
        # Entirely within post_gap.
        return substr($self->{post_gap}, $start - $pre_len, $end - $start);
    }
    else {
        # Straddles the gap boundary -- concat only the needed slices,
        # not the whole document.
        return substr($self->{pre_gap}, $start) . substr($self->{post_gap}, 0, $end - $pre_len);
    }
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

# Binary search the (already-valid) line index for the index of the line
# containing character offset `$offset`. Assumes $self->{_line_index} is
# valid and non-empty. Returns the largest line index i such that
# lines[i].start <= $offset (i.e. the same "which line owns this offset"
# rule used throughout the file, including the last line for offset ==
# length()).
sub _line_index_at_offset {
    my ($self, $offset) = @_;
    my $index = $self->{_line_index};
    my $num_lines = scalar @$index;
    return -1 unless $num_lines;

    my ($lo, $hi) = (0, $num_lines - 1);
    while ($lo < $hi) {
        my $mid = int(($lo + $hi + 1) / 2);
        if ($index->[$mid][0] <= $offset) {
            $lo = $mid;
        } else {
            $hi = $mid - 1;
        }
    }
    return $lo;
}

# Incrementally update the line index after an insert, if possible.
#
# PERFORMANCE: previously every insert() unconditionally invalidated the
# line index, forcing the NEXT line-related call to rebuild it from
# scratch -- a full text() concat + full newline rescan of the entire
# document, once per keystroke on large files.
#
# Fast path: if the index is currently valid and the inserted text
# contains no newline, the edit cannot change which offsets belong to
# which line -- it only grows the line containing `pos` and shifts the
# start offset of every later line by length(text). That's an O(1)
# string-op-free update to the target line plus an O(remaining lines)
# pass of pure integer increments -- no string scanning, no concat.
#
# Slow path (partial win, documented limitation): if the inserted text
# DOES contain a newline (e.g. pressing Enter, or pasting multi-line
# text), splitting/renumbering lines correctly is more involved, so we
# fall back to invalidating the index for a full rebuild on next use.
# This is still a net win in practice: the overwhelming majority of
# edits are single-character, non-newline inserts (typing).
sub _update_line_index_on_insert {
    my ($self, $pos, $text) = @_;

    if ($self->{_line_index_valid} && index($text, "\n") == -1) {
        my $i = $self->_line_index_at_offset($pos);
        if ($i >= 0) {
            my $index = $self->{_line_index};
            my $tlen = CORE::length($text);
            $index->[$i][1] += $tlen;
            for my $j (($i + 1) .. $#$index) {
                $index->[$j][0] += $tlen;
            }
            return;
        }
    }

    $self->{_line_index_valid} = 0;
}

# Incrementally update the line index after a delete, if possible.
# Mirror image of _update_line_index_on_insert: if the deleted text
# contains no newline, it cannot have removed a line boundary, so it
# must lie entirely within the line containing `pos`. Shrink that
# line and shift later lines' start offsets by -length(deleted).
#
# Slow path (partial win, documented limitation): deletions that remove
# a newline (merging lines, or spanning multiple lines) fall back to a
# full rebuild on next use, same reasoning as insert above.
sub _update_line_index_on_delete {
    my ($self, $pos, $deleted) = @_;

    if ($self->{_line_index_valid} && CORE::length($deleted) > 0 && index($deleted, "\n") == -1) {
        my $i = $self->_line_index_at_offset($pos);
        if ($i >= 0) {
            my $index = $self->{_line_index};
            my $dlen = CORE::length($deleted);
            $index->[$i][1] -= $dlen;
            for my $j (($i + 1) .. $#$index) {
                $index->[$j][0] -= $dlen;
            }
            return;
        }
    }

    $self->{_line_index_valid} = 0 if CORE::length($deleted) > 0;
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

    my $lo = $self->_line_index_at_offset($offset);
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

# -----------------------------------------------------------------------------
# Debugging
# -----------------------------------------------------------------------------

# Dump buffer state for debugging
sub _debug_state {
    my ($self) = @_;
    return sprintf("pre_gap[%d]='%s' | post_gap[%d]='%s'",
        CORE::length($self->{pre_gap}), $self->{pre_gap},
        CORE::length($self->{post_gap}), $self->{post_gap});
}

1;
