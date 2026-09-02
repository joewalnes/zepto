package Zepto::View;
# View: viewport into a document (cursor, selection, scroll)
# Manages the visual state independent of the document content

use strict;
use warnings;

# Default viewport size
use constant {
    DEFAULT_VIEWPORT_ROWS => 24,
    DEFAULT_VIEWPORT_COLS => 80,
};

# Horizontal scroll settings
use constant {
    SCROLL_TARGET_POS => 0.75,  # Cursor stays at 75% from left
    SCROLL_LEFT_ZONE  => 0.20,  # Don't scroll if cursor in left 20%
    SCROLL_EOL_ZONE   => 0.40,  # Snap to EOL when within 40% of line end
};

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
        document => $opts{document},

        # Cursor position (0-indexed line and column)
        cursor_line => 0,
        cursor_col  => 0,

        # Selection: if defined, selection is from anchor to cursor
        # anchor is where selection started, cursor is where it ends
        selection_anchor_line => undef,
        selection_anchor_col  => undef,

        # Viewport: top-left corner of visible area
        scroll_line => 0,
        scroll_col  => 0,

        # Viewport size (set by editor based on terminal size)
        viewport_rows => $opts{viewport_rows} // DEFAULT_VIEWPORT_ROWS,
        viewport_cols => $opts{viewport_cols} // DEFAULT_VIEWPORT_COLS,

        # Preferred column for vertical movement (to handle short lines)
        _preferred_col => 0,

        # LineMap for inline diff expansion (undef when no hunks expanded)
        line_map => undef,

        # WrapMap for word wrap mode (undef when word wrap is off)
        _wrap_map => undef,

        # Visual row offset within scroll_line when word wrap is active
        # e.g., if scroll_line=5 and _scroll_wrap_offset=2, viewport starts
        # at the 3rd visual row of document line 5
        _scroll_wrap_offset => 0,

        # Cursor affinity for wrap segment boundaries:
        # 'right' (default) = cursor at boundary belongs to next segment
        # 'left' = cursor at boundary belongs to current segment (used by END key)
        _cursor_affinity => 'right',

        # Per-view word wrap override:
        # undef = use filetype/global default, 0 = forced off, 1 = forced on
        _word_wrap => undef,

        # Column (rectangular) selection mode
        column_select => 0,

        # Multi-cursor: array of secondary cursors (primary is the main cursor/selection)
        # Each entry: { line => N, col => N, anchor_line => N, anchor_col => N }
        # anchor_line/col are for selection at that cursor (undef = no selection)
        _multi_cursors => [],
    }, $class;

    return $self;
}

sub line_map     { $_[0]->{line_map} }
sub set_line_map { $_[0]->{line_map} = $_[1] }

sub wrap_map     { $_[0]->{_wrap_map} }
sub set_wrap_map { $_[0]->{_wrap_map} = $_[1]; $_[0]->{_scroll_wrap_offset} = 0; }
sub invalidate_wrap_map { $_[0]->{_wrap_map}->invalidate() if $_[0]->{_wrap_map} }
sub invalidate_wrap_line {
    my ($self, $line_idx) = @_;
    $self->{_wrap_map}->invalidate_line($line_idx) if $self->{_wrap_map};
}
sub scroll_wrap_offset { $_[0]->{_scroll_wrap_offset} }
sub cursor_affinity { $_[0]->{_cursor_affinity} // 'right' }

sub word_wrap_override     { $_[0]->{_word_wrap} }
sub set_word_wrap_override { $_[0]->{_word_wrap} = $_[1] }

# Compute the effective scroll visual row (used by renderer and coordinate conversion)
sub scroll_visual_row {
    my ($self) = @_;
    my $wm = $self->{_wrap_map};
    return 0 unless $wm;
    return $wm->doc_line_to_visual_row($self->{scroll_line}) + ($self->{_scroll_wrap_offset} // 0);
}

# ============================================================================
# Document access
# ============================================================================

sub document { $_[0]->{document} }
sub set_document { $_[0]->{document} = $_[1] }

# ============================================================================
# Cursor management
# ============================================================================

sub cursor_line { $_[0]->{cursor_line} }
sub cursor_col { $_[0]->{cursor_col} }

sub cursor {
    my ($self) = @_;
    return ($self->{cursor_line}, $self->{cursor_col});
}

sub set_cursor {
    my ($self, $line, $col, $extend_selection, $affinity) = @_;

    my $doc = $self->{document};
    return unless $doc;

    # Clamp line
    my $max_line = $doc->line_count() - 1;
    $max_line = 0 if $max_line < 0;
    $line = 0 if $line < 0;
    $line = $max_line if $line > $max_line;

    # Clamp column to line length (skip upper clamp in column select mode
    # to allow virtual whitespace positioning past line end)
    $col = 0 if $col < 0;
    if ($self->{column_select}) {
        # Virtual whitespace: no upper clamp in column mode
    } else {
        my $max_col = $doc->line_length($line);
        $col = $max_col if $col > $max_col;
    }

    # Handle selection extension
    if ($extend_selection) {
        $self->_start_selection_if_needed();
    }
    else {
        $self->clear_selection();
    }

    $self->{cursor_line} = $line;
    $self->{cursor_col} = $col;
    $self->{_cursor_affinity} = $affinity // 'right';

    # In wrap mode, preferred_col is the visual column within the wrap row
    if ($self->{_wrap_map}) {
        my (undef, $vcol) = $self->{_wrap_map}->doc_to_visual($line, $col, $self->{_cursor_affinity});
        $self->{_preferred_col} = $vcol;
    } else {
        $self->{_preferred_col} = $col;
    }

    $self->ensure_cursor_visible();
}

# Re-clamp every document position this view holds -- cursor, selection
# anchor, multi-cursors and their anchors, and the scroll position -- into
# the document's CURRENT bounds.
#
# Why this exists: set_cursor() clamps, but undo/redo mutate the document
# underneath the view without routing through it. After undoing a multi-line
# paste the document can be many lines shorter than the cursor's recorded
# line, leaving the cursor outside the valid line range. That is not merely
# cosmetic -- line_col_to_offset() saturates at the end of the buffer, so the
# next typed character lands at end-of-document instead of where the cursor
# appears, silently corrupting the file (ASKS.md item 0 / QA-REG-230).
#
# Returns true if anything actually had to be moved, false if the view was
# already in bounds.
sub clamp_to_document {
    my ($self) = @_;

    my $doc = $self->{document};
    return 0 unless $doc;

    my $max_line = $doc->line_count() - 1;
    $max_line = 0 if $max_line < 0;

    my $changed = 0;

    # Clamps one (line, col) pair using the same rules as set_cursor().
    my $clamp = sub {
        my ($line, $col) = @_;

        my $l = (!defined($line) || $line < 0) ? 0 : $line;
        $l = $max_line if $l > $max_line;

        my $c = (!defined($col) || $col < 0) ? 0 : $col;
        # Column-select mode intentionally allows virtual whitespace past the
        # end of a line, so only the line is clamped there -- same exemption
        # set_cursor() makes.
        unless ($self->{column_select}) {
            my $max_col = $doc->line_length($l);
            $c = $max_col if $c > $max_col;
        }

        $changed = 1 if !defined($line) || !defined($col)
                     || $l != $line || $c != $col;
        return ($l, $c);
    };

    ($self->{cursor_line}, $self->{cursor_col}) =
        $clamp->($self->{cursor_line}, $self->{cursor_col});
    my $cursor_moved = $changed;

    if (defined $self->{selection_anchor_line}) {
        ($self->{selection_anchor_line}, $self->{selection_anchor_col}) =
            $clamp->($self->{selection_anchor_line}, $self->{selection_anchor_col});
    }

    for my $mc (@{ $self->{_multi_cursors} }) {
        ($mc->{line}, $mc->{col}) = $clamp->($mc->{line}, $mc->{col});
        if (defined $mc->{anchor_line}) {
            ($mc->{anchor_line}, $mc->{anchor_col}) =
                $clamp->($mc->{anchor_line}, $mc->{anchor_col});
        }
    }

    # The scroll position indexes lines too, and can be left pointing past the
    # end of a shrunken document.
    if ($self->{scroll_line} < 0 || $self->{scroll_line} > $max_line) {
        $self->{scroll_line} = $self->{scroll_line} < 0 ? 0 : $max_line;
        $changed = 1;
    }

    # Only disturb the preferred column and viewport when the cursor itself
    # actually moved -- an already-in-bounds view must be left exactly as it
    # was, so this is a no-op in the common case.
    if ($cursor_moved) {
        if ($self->{_wrap_map}) {
            my (undef, $vcol) = $self->{_wrap_map}->doc_to_visual(
                $self->{cursor_line}, $self->{cursor_col}, $self->{_cursor_affinity});
            $self->{_preferred_col} = $vcol;
        } else {
            $self->{_preferred_col} = $self->{cursor_col};
        }
        $self->ensure_cursor_visible();
    }

    return $changed ? 1 : 0;
}

# Get cursor as byte offset in document
sub cursor_offset {
    my ($self) = @_;
    return $self->{document}->line_col_to_offset(
        $self->{cursor_line},
        $self->{cursor_col}
    );
}

# Set cursor from byte offset
sub set_cursor_from_offset {
    my ($self, $offset, $extend_selection) = @_;
    my ($line, $col) = $self->{document}->offset_to_line_col($offset);
    $self->set_cursor($line, $col, $extend_selection);
}

# ============================================================================
# Cursor movement
# ============================================================================

sub move_left {
    my ($self, $extend_selection) = @_;

    if ($self->{cursor_col} > 0) {
        $self->set_cursor($self->{cursor_line}, $self->{cursor_col} - 1, $extend_selection);
    }
    elsif (!$self->{column_select} && $self->{cursor_line} > 0) {
        # Wrap to end of previous line (disabled in column mode)
        my $prev_line = $self->{cursor_line} - 1;
        my $end_col = $self->{document}->line_length($prev_line);
        $self->set_cursor($prev_line, $end_col, $extend_selection);
    }
}

sub move_right {
    my ($self, $extend_selection) = @_;

    my $line_len = $self->{document}->line_length($self->{cursor_line});

    if ($self->{column_select}) {
        # In column mode, allow cursor past end of line (virtual space)
        $self->set_cursor($self->{cursor_line}, $self->{cursor_col} + 1, $extend_selection);
    }
    elsif ($self->{cursor_col} < $line_len) {
        $self->set_cursor($self->{cursor_line}, $self->{cursor_col} + 1, $extend_selection);
    }
    elsif ($self->{cursor_line} < $self->{document}->line_count() - 1) {
        # Wrap to start of next line
        $self->set_cursor($self->{cursor_line} + 1, 0, $extend_selection);
    }
}

sub move_up {
    my ($self, $extend_selection) = @_;

    my $wm = $self->{_wrap_map};
    if ($wm) {
        # Word wrap: move one visual row up
        my ($cur_vrow, $cur_vcol) = $wm->doc_to_visual($self->{cursor_line}, $self->{cursor_col}, $self->{_cursor_affinity});
        if ($cur_vrow > 0) {
            my ($new_line, $new_col) = $wm->visual_to_doc($cur_vrow - 1, $self->{_preferred_col});
            my $max_col = $self->{document}->line_length($new_line);
            $new_col = $max_col if $new_col > $max_col;

            if ($extend_selection) { $self->_start_selection_if_needed(); }
            else { $self->clear_selection(); }

            $self->{cursor_line} = $new_line;
            $self->{cursor_col} = $new_col;
            $self->{_cursor_affinity} = 'right';
            $self->ensure_cursor_visible();
        }
        return;
    }

    if ($self->{cursor_line} > 0) {
        my $new_line = $self->{cursor_line} - 1;
        my $new_col = $self->{_preferred_col};

        # In column select mode with extend, allow virtual whitespace
        unless ($self->{column_select} && $extend_selection) {
            my $max_col = $self->{document}->line_length($new_line);
            $new_col = $max_col if $new_col > $max_col;
        }

        if ($extend_selection) {
            $self->_start_selection_if_needed();
        }
        else {
            $self->clear_selection();
        }

        $self->{cursor_line} = $new_line;
        $self->{cursor_col} = $new_col;
        # Don't update preferred_col on vertical movement
        $self->ensure_cursor_visible();
    }
}

sub move_down {
    my ($self, $extend_selection) = @_;

    my $wm = $self->{_wrap_map};
    if ($wm) {
        # Word wrap: move one visual row down
        my ($cur_vrow, $cur_vcol) = $wm->doc_to_visual($self->{cursor_line}, $self->{cursor_col}, $self->{_cursor_affinity});
        if ($cur_vrow < $wm->total_visual_rows() - 1) {
            my ($new_line, $new_col) = $wm->visual_to_doc($cur_vrow + 1, $self->{_preferred_col});
            my $max_col = $self->{document}->line_length($new_line);
            $new_col = $max_col if $new_col > $max_col;

            if ($extend_selection) { $self->_start_selection_if_needed(); }
            else { $self->clear_selection(); }

            $self->{cursor_line} = $new_line;
            $self->{cursor_col} = $new_col;
            $self->{_cursor_affinity} = 'right';
            $self->ensure_cursor_visible();
        }
        return;
    }

    if ($self->{cursor_line} < $self->{document}->line_count() - 1) {
        my $new_line = $self->{cursor_line} + 1;
        my $new_col = $self->{_preferred_col};

        # In column select mode with extend, allow virtual whitespace
        unless ($self->{column_select} && $extend_selection) {
            my $max_col = $self->{document}->line_length($new_line);
            $new_col = $max_col if $new_col > $max_col;
        }

        if ($extend_selection) {
            $self->_start_selection_if_needed();
        }
        else {
            $self->clear_selection();
        }

        $self->{cursor_line} = $new_line;
        $self->{cursor_col} = $new_col;
        $self->ensure_cursor_visible();
    }
}

sub move_to_line_start {
    my ($self, $extend_selection) = @_;
    my $line = $self->{cursor_line};
    my $col  = $self->{cursor_col};
    my $content = $self->{document}->get_line_content($line);

    # Find first non-whitespace column
    my $first_nonws = 0;
    if ($content =~ /^(\s+)/) {
        $first_nonws = CORE::length($1);
    }

    my $wm = $self->{_wrap_map};
    if ($wm) {
        # In word-wrap mode, smart home cycles: first-nonws → visual row start → doc start
        my ($cur_vrow, $cur_vcol) = $wm->doc_to_visual($line, $col, $self->{_cursor_affinity});
        my ($row_start_line, $row_start_col) = $wm->visual_to_doc($cur_vrow, 0);

        my $seg = $wm->segment_at_visual_row($cur_vrow);
        if ($seg && $seg->{wrap_index} == 0) {
            # First visual row: cycle first-nonws → col 0 → doc start
            if ($col == 0) {
                $self->move_to_document_start($extend_selection);
            } elsif ($col == $first_nonws || $first_nonws == 0) {
                $self->set_cursor($line, 0, $extend_selection);
            } else {
                $self->set_cursor($line, $first_nonws, $extend_selection);
            }
        } else {
            # Continuation row: cycle row start → doc start
            if ($col != $row_start_col || $line != $row_start_line) {
                $self->set_cursor($row_start_line, $row_start_col, $extend_selection);
            } else {
                $self->move_to_document_start($extend_selection);
            }
        }
        return;
    }

    # Smart home: cycle first-nonws → col 0 → document start
    # Check col 0 first (otherwise col=0 with first_nonws>0 re-enters the cycle)
    if ($col == 0) {
        $self->move_to_document_start($extend_selection);
    } elsif ($col == $first_nonws || $first_nonws == 0) {
        $self->set_cursor($line, 0, $extend_selection);
    } else {
        $self->set_cursor($line, $first_nonws, $extend_selection);
    }
}

sub move_to_line_end {
    my ($self, $extend_selection) = @_;
    my $wm = $self->{_wrap_map};
    if ($wm) {
        # Smart end in wrap mode: visual row end → document end
        my ($cur_vrow, $cur_vcol) = $wm->doc_to_visual($self->{cursor_line}, $self->{cursor_col}, $self->{_cursor_affinity});
        my $seg = $wm->segment_at_visual_row($cur_vrow);
        if ($seg) {
            my $line_len = $self->{document}->line_length($seg->{doc_line});
            my $end_col = $seg->{col_end};
            $end_col = $line_len if $end_col > $line_len;
            if ($self->{cursor_line} == $seg->{doc_line} && $self->{cursor_col} == $end_col) {
                # Already at visual row end — go to document end
                $self->move_to_document_end($extend_selection);
            } else {
                # Use 'left' affinity so cursor renders at end of THIS visual row,
                # not at start of next row (col_end is a segment boundary)
                $self->set_cursor($seg->{doc_line}, $end_col, $extend_selection, 'left');
            }
            return;
        }
    }
    my $line_end = $self->{document}->line_length($self->{cursor_line});
    # Smart end: if already at line end, go to document end
    if ($self->{cursor_col} == $line_end) {
        $self->move_to_document_end($extend_selection);
    } else {
        $self->set_cursor($self->{cursor_line}, $line_end, $extend_selection);
    }
}

sub move_to_document_start {
    my ($self, $extend_selection) = @_;
    $self->set_cursor(0, 0, $extend_selection);
}

sub move_to_document_end {
    my ($self, $extend_selection) = @_;
    my $last_line = $self->{document}->line_count() - 1;
    $last_line = 0 if $last_line < 0;
    my $end_col = $self->{document}->line_length($last_line);
    $self->set_cursor($last_line, $end_col, $extend_selection);
}

sub move_page_up {
    my ($self, $extend_selection) = @_;
    my $page_size = $self->{viewport_rows} - 1;
    $page_size = 1 if $page_size < 1;

    my $wm = $self->{_wrap_map};
    if ($wm) {
        my ($cur_vrow, $cur_vcol) = $wm->doc_to_visual($self->{cursor_line}, $self->{cursor_col}, $self->{_cursor_affinity});
        my $target_vrow = $cur_vrow - $page_size;
        $target_vrow = 0 if $target_vrow < 0;
        my ($new_line, $new_col) = $wm->visual_to_doc($target_vrow, $self->{_preferred_col});
        my $max_col = $self->{document}->line_length($new_line);
        $new_col = $max_col if $new_col > $max_col;

        if ($extend_selection) { $self->_start_selection_if_needed(); }
        else { $self->clear_selection(); }

        $self->{cursor_line} = $new_line;
        $self->{cursor_col} = $new_col;
        $self->{_cursor_affinity} = 'right';
        $self->ensure_cursor_visible();
        return;
    }

    my $new_line = $self->{cursor_line} - $page_size;
    $new_line = 0 if $new_line < 0;

    if ($extend_selection) {
        $self->_start_selection_if_needed();
    }
    else {
        $self->clear_selection();
    }

    $self->{cursor_line} = $new_line;
    my $max_col = $self->{document}->line_length($new_line);
    $self->{cursor_col} = $self->{_preferred_col};
    $self->{cursor_col} = $max_col if $self->{cursor_col} > $max_col;

    $self->ensure_cursor_visible();
}

sub move_page_down {
    my ($self, $extend_selection) = @_;
    my $page_size = $self->{viewport_rows} - 1;
    $page_size = 1 if $page_size < 1;

    my $wm = $self->{_wrap_map};
    if ($wm) {
        my ($cur_vrow, $cur_vcol) = $wm->doc_to_visual($self->{cursor_line}, $self->{cursor_col}, $self->{_cursor_affinity});
        my $max_vrow = $wm->total_visual_rows() - 1;
        my $target_vrow = $cur_vrow + $page_size;
        $target_vrow = $max_vrow if $target_vrow > $max_vrow;
        my ($new_line, $new_col) = $wm->visual_to_doc($target_vrow, $self->{_preferred_col});
        my $max_col = $self->{document}->line_length($new_line);
        $new_col = $max_col if $new_col > $max_col;

        if ($extend_selection) { $self->_start_selection_if_needed(); }
        else { $self->clear_selection(); }

        $self->{cursor_line} = $new_line;
        $self->{cursor_col} = $new_col;
        $self->{_cursor_affinity} = 'right';
        $self->ensure_cursor_visible();
        return;
    }

    my $max_line = $self->{document}->line_count() - 1;
    my $new_line = $self->{cursor_line} + $page_size;
    $new_line = $max_line if $new_line > $max_line;

    if ($extend_selection) {
        $self->_start_selection_if_needed();
    }
    else {
        $self->clear_selection();
    }

    $self->{cursor_line} = $new_line;
    my $max_col = $self->{document}->line_length($new_line);
    $self->{cursor_col} = $self->{_preferred_col};
    $self->{cursor_col} = $max_col if $self->{cursor_col} > $max_col;

    $self->ensure_cursor_visible();
}

# Word movement
sub move_word_left {
    my ($self, $extend_selection) = @_;

    my $line = $self->{document}->get_line_content($self->{cursor_line});
    my $col = $self->{cursor_col};

    if ($col == 0) {
        # At line start, move to end of previous line
        if ($self->{cursor_line} > 0) {
            my $prev_line = $self->{cursor_line} - 1;
            my $end_col = $self->{document}->line_length($prev_line);
            $self->set_cursor($prev_line, $end_col, $extend_selection);
        }
        return;
    }

    # Skip spaces backwards
    while ($col > 0 && substr($line, $col - 1, 1) =~ /\s/) {
        $col--;
    }

    # Determine character class and skip that class backwards
    if ($col > 0) {
        my $char = substr($line, $col - 1, 1);
        if ($char =~ /\w/) {
            # Skip word characters backwards
            while ($col > 0 && substr($line, $col - 1, 1) =~ /\w/) {
                $col--;
            }
        } else {
            # Skip punctuation/symbols backwards
            while ($col > 0 && substr($line, $col - 1, 1) =~ /[^\w\s]/) {
                $col--;
            }
        }
    }

    $self->set_cursor($self->{cursor_line}, $col, $extend_selection);
}

sub move_word_right {
    my ($self, $extend_selection) = @_;

    my $line = $self->{document}->get_line_content($self->{cursor_line});
    my $col = $self->{cursor_col};
    my $len = CORE::length($line);

    if ($col >= $len) {
        # At line end, move to start of next line
        if ($self->{cursor_line} < $self->{document}->line_count() - 1) {
            $self->set_cursor($self->{cursor_line} + 1, 0, $extend_selection);
        }
        return;
    }

    # Determine character class and skip that class forward
    my $char = substr($line, $col, 1);
    if ($char =~ /\w/) {
        # Skip word characters forward
        while ($col < $len && substr($line, $col, 1) =~ /\w/) {
            $col++;
        }
    } elsif ($char =~ /[^\s]/) {
        # Skip punctuation/symbols forward
        while ($col < $len && substr($line, $col, 1) =~ /[^\w\s]/) {
            $col++;
        }
    }

    # Skip spaces forward
    while ($col < $len && substr($line, $col, 1) =~ /\s/) {
        $col++;
    }

    $self->set_cursor($self->{cursor_line}, $col, $extend_selection);
}

# Go to specific line (1-indexed for user interface)
sub goto_line {
    my ($self, $line_num) = @_;
    # Convert from 1-indexed (user) to 0-indexed (internal)
    $line_num = $line_num - 1;
    $line_num = 0 if $line_num < 0;
    my $max_line = $self->{document}->line_count() - 1;
    $line_num = $max_line if $line_num > $max_line;

    $self->clear_selection();
    $self->set_cursor($line_num, 0, 0);
}

# ============================================================================
# Selection management
# ============================================================================

sub has_selection {
    my ($self) = @_;
    return defined $self->{selection_anchor_line};
}

sub _start_selection_if_needed {
    my ($self) = @_;
    return if $self->has_selection();
    $self->{selection_anchor_line} = $self->{cursor_line};
    $self->{selection_anchor_col} = $self->{cursor_col};
}

sub clear_selection {
    my ($self) = @_;
    $self->{selection_anchor_line} = undef;
    $self->{selection_anchor_col} = undef;
    $self->{column_select} = 0;
}

# Get selection as (start_line, start_col, end_line, end_col)
# Normalized so start <= end
sub selection {
    my ($self) = @_;
    return () unless $self->has_selection();

    my ($al, $ac) = ($self->{selection_anchor_line}, $self->{selection_anchor_col});
    my ($cl, $cc) = ($self->{cursor_line}, $self->{cursor_col});

    # Normalize: start should be before end
    if ($al > $cl || ($al == $cl && $ac > $cc)) {
        return ($cl, $cc, $al, $ac);
    }
    return ($al, $ac, $cl, $cc);
}

# Get selection as byte offsets (start, end)
sub selection_offsets {
    my ($self) = @_;
    return () unless $self->has_selection();

    my ($sl, $sc, $el, $ec) = $self->selection();
    my $start = $self->{document}->line_col_to_offset($sl, $sc);
    my $end = $self->{document}->line_col_to_offset($el, $ec);

    return ($start, $end);
}

# Get selected text
sub selected_text {
    my ($self) = @_;
    return '' unless $self->has_selection();

    my ($start, $end) = $self->selection_offsets();
    return $self->{document}->get_text($start, $end);
}

# Select all text
sub select_all {
    my ($self) = @_;
    $self->{selection_anchor_line} = 0;
    $self->{selection_anchor_col} = 0;
    $self->move_to_document_end(0);  # Don't extend, just move
    # But we want selection, so set anchor back
    $self->{selection_anchor_line} = 0;
    $self->{selection_anchor_col} = 0;
}

# Select word at cursor
sub select_word {
    my ($self) = @_;

    my $line = $self->{document}->get_line_content($self->{cursor_line});
    my $col = $self->{cursor_col};
    my $len = CORE::length($line);

    return if $len == 0;

    # Find word boundaries
    my $start = $col;
    my $end = $col;

    # If on a word character, select the word
    if ($col < $len && substr($line, $col, 1) =~ /\w/) {
        while ($start > 0 && substr($line, $start - 1, 1) =~ /\w/) {
            $start--;
        }
        while ($end < $len && substr($line, $end, 1) =~ /\w/) {
            $end++;
        }
    }
    # If on whitespace, select the whitespace
    elsif ($col < $len && substr($line, $col, 1) =~ /\s/) {
        while ($start > 0 && substr($line, $start - 1, 1) =~ /\s/) {
            $start--;
        }
        while ($end < $len && substr($line, $end, 1) =~ /\s/) {
            $end++;
        }
    }

    $self->{selection_anchor_line} = $self->{cursor_line};
    $self->{selection_anchor_col} = $start;
    $self->{cursor_col} = $end;
    $self->{_preferred_col} = $end;
}

# Select current line
sub select_line {
    my ($self) = @_;
    my $line = $self->{cursor_line};

    $self->{selection_anchor_line} = $line;
    $self->{selection_anchor_col} = 0;

    # Include newline if not last line
    if ($line < $self->{document}->line_count() - 1) {
        $self->{cursor_line} = $line + 1;
        $self->{cursor_col} = 0;
    }
    else {
        $self->{cursor_col} = $self->{document}->line_length($line);
    }
    $self->{_preferred_col} = $self->{cursor_col};
}

# ============================================================================
# Multi-cursor support
# ============================================================================

sub has_multi_cursors { scalar @{$_[0]->{_multi_cursors}} > 0 }
sub multi_cursors     { $_[0]->{_multi_cursors} }

# Total number of cursors (primary + secondary)
sub cursor_count { 1 + scalar @{$_[0]->{_multi_cursors}} }

sub clear_multi_cursors {
    my ($self) = @_;
    $self->{_multi_cursors} = [];
}

# Add a secondary cursor with optional selection (anchor).
sub add_multi_cursor {
    my ($self, %opts) = @_;
    push @{$self->{_multi_cursors}}, {
        line        => $opts{line},
        col         => $opts{col},
        anchor_line => $opts{anchor_line},
        anchor_col  => $opts{anchor_col},
    };
}

# Return all cursor positions sorted by document order (primary + secondary).
# Each entry: { line, col, anchor_line, anchor_col, is_primary }
# Sorted in ascending document order (by line, then col).
sub all_cursors_sorted {
    my ($self) = @_;
    my @all;

    # Primary cursor
    push @all, {
        line        => $self->{cursor_line},
        col         => $self->{cursor_col},
        anchor_line => $self->{selection_anchor_line},
        anchor_col  => $self->{selection_anchor_col},
        is_primary  => 1,
    };

    # Secondary cursors
    for my $mc (@{$self->{_multi_cursors}}) {
        push @all, {
            line        => $mc->{line},
            col         => $mc->{col},
            anchor_line => $mc->{anchor_line},
            anchor_col  => $mc->{anchor_col},
            is_primary  => 0,
        };
    }

    # Sort by line, then col (ascending)
    @all = sort { $a->{line} <=> $b->{line} || $a->{col} <=> $b->{col} } @all;
    return @all;
}

# Check if a position already has a cursor (to avoid duplicates).
sub has_cursor_at {
    my ($self, $line, $col) = @_;
    return 1 if $self->{cursor_line} == $line && $self->{cursor_col} == $col;
    for my $mc (@{$self->{_multi_cursors}}) {
        return 1 if $mc->{line} == $line && $mc->{col} == $col;
    }
    return 0;
}

# ============================================================================
# Viewport management
# ============================================================================

sub scroll_line { $_[0]->{scroll_line} }
sub scroll_col { $_[0]->{scroll_col} }

sub set_viewport_size {
    my ($self, $rows, $cols) = @_;
    $self->{viewport_rows} = $rows;
    $self->{viewport_cols} = $cols;
    $self->ensure_cursor_visible();
}

sub viewport_rows { $_[0]->{viewport_rows} }
sub viewport_cols { $_[0]->{viewport_cols} }

# Get range of visible lines (document lines)
# When hunks are expanded, may return fewer doc lines than viewport_rows
# since old-line rows consume display space
sub visible_line_range {
    my ($self) = @_;
    my $start = $self->{scroll_line};
    my $max = $self->{document}->line_count();

    my $wm = $self->{_wrap_map};
    if ($wm) {
        my $scroll_vrow = $self->scroll_visual_row();
        my $end_line = $start;
        for my $i (0 .. $self->{viewport_rows} - 1) {
            my $seg = $wm->segment_at_visual_row($scroll_vrow + $i);
            if ($seg && $seg->{doc_line} >= $end_line) {
                $end_line = $seg->{doc_line} + 1;
            }
        }
        $end_line = $max if $end_line > $max;
        return ($start, $end_line);
    }

    my $lm = $self->{line_map};
    if ($lm && $lm->has_expanded_hunks()) {
        # Walk visible entries to find the last doc line shown
        my $entries = $lm->visible_entries($start, $self->{viewport_rows});
        my $end_line = $start;
        for my $entry (@$entries) {
            if ($entry->{type} eq 'doc' && $entry->{line} >= $end_line) {
                $end_line = $entry->{line} + 1;
            }
        }
        $end_line = $max if $end_line > $max;
        return ($start, $end_line);
    }

    my $end = $start + $self->{viewport_rows};
    $end = $max if $end > $max;
    return ($start, $end);
}

# Ensure cursor is within visible viewport
sub ensure_cursor_visible {
    my ($self) = @_;

    # After explicit viewport scroll (mouse wheel), don't snap viewport back
    # to cursor — allow the user to scroll freely away from the cursor position.
    # Flag persists until cleared by the next non-scroll user event.
    if ($self->{_explicit_scroll}) {
        return;
    }

    # Word wrap mode: scroll by visual rows, no horizontal scroll
    my $wm = $self->{_wrap_map};
    if ($wm) {
        $self->{scroll_col} = 0;

        my ($cursor_vrow, $_vcol) = $wm->doc_to_visual($self->{cursor_line}, $self->{cursor_col}, $self->{_cursor_affinity});
        my $scroll_vrow = $self->scroll_visual_row();

        if ($cursor_vrow < $scroll_vrow) {
            # Cursor above viewport: scroll up to show cursor at top
            my $seg = $wm->segment_at_visual_row($cursor_vrow);
            if ($seg) {
                $self->{scroll_line} = $seg->{doc_line};
                my $line_start_vrow = $wm->doc_line_to_visual_row($seg->{doc_line});
                $self->{_scroll_wrap_offset} = $cursor_vrow - $line_start_vrow;
            } else {
                $self->{scroll_line} = 0;
                $self->{_scroll_wrap_offset} = 0;
            }
        }
        elsif ($cursor_vrow >= $scroll_vrow + $self->{viewport_rows}) {
            # Cursor below viewport: scroll down so cursor is at bottom
            my $target_vrow = $cursor_vrow - $self->{viewport_rows} + 1;
            my $seg = $wm->segment_at_visual_row($target_vrow);
            if ($seg) {
                $self->{scroll_line} = $seg->{doc_line};
                my $line_start_vrow = $wm->doc_line_to_visual_row($seg->{doc_line});
                $self->{_scroll_wrap_offset} = $target_vrow - $line_start_vrow;
            } else {
                $self->{scroll_line} = 0;
                $self->{_scroll_wrap_offset} = 0;
            }
        }

        $self->{scroll_line} = 0 if $self->{scroll_line} < 0;
        return;
    }

    # Vertical scrolling (no margins - scroll exactly when needed)
    my $lm = $self->{line_map};
    if ($lm && $lm->has_expanded_hunks()) {
        # With expanded hunks, we need to account for old-line rows
        # consuming viewport space between scroll_line and cursor_line
        if ($self->{cursor_line} < $self->{scroll_line}) {
            $self->{scroll_line} = $self->{cursor_line};
        } else {
            my $cursor_display = $lm->doc_line_to_display($self->{cursor_line});
            my $scroll_display = $lm->doc_line_to_display($self->{scroll_line});
            my $display_span = $cursor_display - $scroll_display + 1;
            if ($display_span > $self->{viewport_rows}) {
                # Need to scroll down — find a scroll_line where cursor fits
                # Walk backwards from cursor to find a doc line that puts cursor in viewport
                my $target_display = $cursor_display - $self->{viewport_rows} + 1;
                # Find the doc line at or after target_display
                my $new_scroll = $self->{cursor_line};
                while ($new_scroll > 0 &&
                       $lm->doc_line_to_display($new_scroll - 1) >= $target_display) {
                    $new_scroll--;
                }
                $self->{scroll_line} = $new_scroll;
            }
        }
    } else {
        if ($self->{cursor_line} < $self->{scroll_line}) {
            $self->{scroll_line} = $self->{cursor_line};
        }
        elsif ($self->{cursor_line} >= $self->{scroll_line} + $self->{viewport_rows}) {
            $self->{scroll_line} = $self->{cursor_line} - $self->{viewport_rows} + 1;
        }
    }

    # Horizontal scrolling - keep cursor in a comfortable zone with context ahead
    my $cols = $self->{viewport_cols};
    my $line_len = $self->{document}->line_length($self->{cursor_line});
    my $cursor_col = $self->{cursor_col};

    # Short line that fits in viewport - no horizontal scroll needed
    if ($line_len <= $cols) {
        $self->{scroll_col} = 0;
    }
    else {
        # Long line - keep cursor in sweet spot with context ahead
        my $target_pos = int($cols * SCROLL_TARGET_POS);
        my $left_zone = int($cols * SCROLL_LEFT_ZONE);

        # Calculate where cursor appears in current viewport
        my $cursor_screen_pos = $cursor_col - $self->{scroll_col};

        # Near end of line - show the line end
        if ($line_len - $cursor_col < int($cols * SCROLL_EOL_ZONE)) {
            $self->{scroll_col} = $line_len - $cols + 1;
        }
        # Cursor too far right - scroll to put cursor at target position
        elsif ($cursor_screen_pos > $target_pos) {
            $self->{scroll_col} = $cursor_col - $target_pos;
        }
        # Cursor too far left - scroll to keep some left context
        elsif ($cursor_screen_pos < $left_zone && $self->{scroll_col} > 0) {
            $self->{scroll_col} = $cursor_col - $left_zone;
        }
    }

    # Clamp scroll
    $self->{scroll_line} = 0 if $self->{scroll_line} < 0;
    $self->{scroll_col} = 0 if $self->{scroll_col} < 0;
}

# Scroll without moving cursor
sub scroll_up {
    my ($self, $lines) = @_;
    $lines //= 1;
    $self->{scroll_line} -= $lines;
    $self->{scroll_line} = 0 if $self->{scroll_line} < 0;
    $self->{_explicit_scroll} = 1;
}

sub scroll_down {
    my ($self, $lines) = @_;
    $lines //= 1;
    my $total_lines = $self->{document}->line_count();
    # Clamp so the last line can never scroll past the bottom of the
    # viewport -- once reached, it stays pinned there rather than rising
    # to the top and leaving the rest of the viewport blank.
    my $max_scroll = $total_lines > $self->{viewport_rows}
        ? $total_lines - $self->{viewport_rows}
        : 0;
    $self->{scroll_line} += $lines;
    $self->{scroll_line} = $max_scroll if $self->{scroll_line} > $max_scroll;
    $self->{_explicit_scroll} = 1;
}

# Clear explicit scroll flag — called at start of each non-scroll event
# so ensure_cursor_visible() resumes normal cursor-following behavior
sub clear_explicit_scroll {
    my ($self) = @_;
    delete $self->{_explicit_scroll};
}

# ============================================================================
# Screen coordinate conversions
# ============================================================================

# Convert document line/col to screen position
# Returns (row, col) relative to text area, or undef if not visible
sub doc_to_screen {
    my ($self, $line, $col) = @_;

    my $wm = $self->{_wrap_map};
    if ($wm) {
        my ($vrow, $vcol) = $wm->doc_to_visual($line, $col);
        my $scroll_vrow = $self->scroll_visual_row();
        my $row = $vrow - $scroll_vrow;
        return (undef, undef) if $row < 0 || $row >= $self->{viewport_rows};
        return ($row, $vcol);
    }

    my $lm = $self->{line_map};
    my $row;
    if ($lm && $lm->has_expanded_hunks()) {
        my $line_display = $lm->doc_line_to_display($line);
        my $scroll_display = $lm->scroll_display_start($self->{scroll_line});
        $row = $line_display - $scroll_display;
    } else {
        $row = $line - $self->{scroll_line};
    }
    my $scol = $col - $self->{scroll_col};

    return (undef, undef) if $row < 0 || $row >= $self->{viewport_rows};
    return (undef, undef) if $scol < 0;  # Col can extend past right edge

    return ($row, $scol);
}

# Convert screen position to document line/col
# Returns ($line, $col) or (undef, undef) if the screen row is an old-line row
sub screen_to_doc {
    my ($self, $row, $col) = @_;

    my $wm = $self->{_wrap_map};
    if ($wm) {
        my $scroll_vrow = $self->scroll_visual_row();
        my $target_vrow = $scroll_vrow + $row;
        my ($line, $dcol) = $wm->visual_to_doc($target_vrow, $col);
        return ($line, $dcol);
    }

    my $lm = $self->{line_map};
    my $line;
    if ($lm && $lm->has_expanded_hunks()) {
        my $scroll_display = $lm->scroll_display_start($self->{scroll_line});
        my $display_row = $scroll_display + $row;
        my $entry = $lm->display_entry($display_row);
        return (undef, undef) unless $entry;
        # Old-line rows have no document line
        return (undef, undef) if $entry->{type} eq 'old';
        $line = $entry->{line};
    } else {
        $line = $self->{scroll_line} + $row;
    }

    my $dcol = $self->{scroll_col} + $col;

    # Clamp to document bounds
    my $max_line = $self->{document}->line_count() - 1;
    $max_line = 0 if $max_line < 0;
    $line = $max_line if $line > $max_line;
    $line = 0 if $line < 0;

    my $max_col = $self->{document}->line_length($line);
    $dcol = $max_col if $dcol > $max_col;
    $dcol = 0 if $dcol < 0;

    return ($line, $dcol);
}

# Check if a line/col is within selection
sub is_selected {
    my ($self, $line, $col) = @_;
    return 0 unless $self->has_selection();

    my ($sl, $sc, $el, $ec) = $self->selection();

    # Before selection start
    return 0 if $line < $sl || ($line == $sl && $col < $sc);

    # After selection end
    return 0 if $line > $el || ($line == $el && $col >= $ec);

    return 1;
}

# ============================================================================
# Column (rectangular) selection
# ============================================================================

sub column_select { $_[0]->{column_select} }

# Enter column mode without forcing a selection
sub enter_column_mode {
    my ($self) = @_;
    $self->clear_selection();
    $self->{column_select} = 1;  # Must be after clear_selection which resets it
}

# Exit column mode and clear any selection
sub exit_column_mode {
    my ($self) = @_;
    $self->{column_select} = 0;
    $self->clear_selection();
}

# Enter column selection mode, setting anchor at current cursor
sub start_column_selection {
    my ($self) = @_;
    $self->{column_select} = 1;
    $self->_start_selection_if_needed();
}

# Get column selection as normalized rectangle: (top, left, bottom, right)
# Returns empty list if not in column mode or no selection
sub column_selection {
    my ($self) = @_;
    return () unless $self->{column_select} && $self->has_selection();

    my ($al, $ac) = ($self->{selection_anchor_line}, $self->{selection_anchor_col});
    my ($cl, $cc) = ($self->{cursor_line}, $self->{cursor_col});

    my $top    = $al < $cl ? $al : $cl;
    my $bottom = $al > $cl ? $al : $cl;
    my $left   = $ac < $cc ? $ac : $cc;
    my $right  = $ac > $cc ? $ac : $cc;

    return ($top, $left, $bottom, $right);
}

# Check if a position is inside the column selection rectangle
sub is_column_selected {
    my ($self, $line, $col) = @_;
    return 0 unless $self->{column_select} && $self->has_selection();

    my ($top, $left, $bottom, $right) = $self->column_selection();
    return ($line >= $top && $line <= $bottom && $col >= $left && $col < $right);
}

# Extract rectangular text as arrayref of strings (one per line).
# Short lines are space-padded to fill the rectangle width.
sub column_selected_text {
    my ($self) = @_;
    return [] unless $self->{column_select} && $self->has_selection();

    my ($top, $left, $bottom, $right) = $self->column_selection();
    my $width = $right - $left;
    my @lines;

    for my $ln ($top .. $bottom) {
        my $content = $self->{document}->get_line_content($ln);
        my $len = CORE::length($content);

        if ($left >= $len) {
            # Entire selection is past line end — all spaces
            push @lines, ' ' x $width;
        } else {
            my $avail = $len - $left;
            my $take = $avail < $width ? $avail : $width;
            my $chunk = substr($content, $left, $take);
            # Pad with spaces if line is shorter than right edge
            if ($take < $width) {
                $chunk .= ' ' x ($width - $take);
            }
            push @lines, $chunk;
        }
    }

    return \@lines;
}

# Get per-line edit ranges for column operations.
# Returns arrayref of {line, start_col, end_col} hashes.
sub column_edit_ranges {
    my ($self) = @_;
    return [] unless $self->{column_select} && $self->has_selection();

    my ($top, $left, $bottom, $right) = $self->column_selection();
    my @ranges;

    for my $ln ($top .. $bottom) {
        push @ranges, {
            line      => $ln,
            start_col => $left,
            end_col   => $right,
        };
    }

    return \@ranges;
}

1;
