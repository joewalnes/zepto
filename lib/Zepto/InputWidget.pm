package Zepto::InputWidget;
# =============================================================================
# Unified text input widget
# =============================================================================
#
# Provides consistent editing semantics across all status-bar inputs:
# Find bar, Go To Line, Save As prompt, and command palette filter.
#
# Supported operations:
#   - Left/Right cursor movement
#   - Alt+Left/Right: word movement
#   - Home/End: line start/end
#   - Shift+[arrow/home/end]: extend selection
#   - Shift+Alt+Left/Right: word selection
#   - Backspace/Delete: delete char (or delete selection)
#   - Ctrl+A: select all
#   - Ctrl+X/C/V: cut/copy/paste (when clipboard_ref provided)
#   - Any printable char: insert (replaces selection)
#   - Mouse click to place cursor (via handle_mouse_click)
#   - Mouse drag to select (via handle_mouse_drag_update / handle_mouse_drag_end)
#
# Overflow: call viewport($width) to get the visible slice and cursor position.
# The widget keeps a view_offset that scrolls to keep the cursor visible.
#
# Keys NOT handled here (caller must handle):
#   Enter, Escape, Tab, Up, Down, and any other special keys.
#   Ctrl chars not listed above return 0 so callers can handle them.
# =============================================================================

use strict;
use warnings;
use utf8;

use Zepto::InputParser;

sub new {
    my ($class, %opts) = @_;
    my $value = $opts{value} // '';
    return bless {
        value       => $value,
        cursor      => length($value),
        sel_start   => undef,
        sel_end     => undef,
        view_offset => 0,
        drag_anchor => undef,
    }, $class;
}

# Accessors
sub value       { $_[0]->{value} }
sub cursor      { $_[0]->{cursor} }
sub sel_start   { $_[0]->{sel_start} }
sub sel_end     { $_[0]->{sel_end} }
sub view_offset { $_[0]->{view_offset} }

# Returns true if a selection is currently active.
sub has_selection { defined $_[0]->{sel_start} }

# Returns (start, end) of the selection with start <= end.
# Returns (undef, undef) if no selection.
sub selection_range {
    my ($self) = @_;
    return (undef, undef) unless defined $self->{sel_start};
    my ($s, $e) = ($self->{sel_start}, $self->{sel_end});
    ($s, $e) = ($e, $s) if $s > $e;
    return ($s, $e);
}

# Returns the selected text, or '' if no selection.
sub selected_text {
    my ($self) = @_;
    my ($s, $e) = $self->selection_range();
    return '' unless defined $s;
    return substr($self->{value}, $s, $e - $s);
}

# Replace the entire value and reset cursor to end, clearing selection.
sub set_value {
    my ($self, $val) = @_;
    $self->{value}       = $val;
    $self->{cursor}      = length($val);
    $self->{view_offset} = 0;
    $self->_clear_selection();
}

# =============================================================================
# Viewport (overflow scrolling)
# =============================================================================

# Returns a hashref describing the visible slice of the input for rendering:
#   display_text      — the $width chars of text that should be shown
#   cursor_in_view    — cursor column within the visible slice (0-indexed)
#   sel_start_in_view — start of visible selection (undef if no/off-screen sel)
#   sel_end_in_view   — end   of visible selection (undef if no/off-screen sel)
#   view_offset       — leftmost visible char index (for click-to-cursor math)
#
# Also updates the internal view_offset to keep the cursor on screen.
sub viewport {
    my ($self, $width) = @_;
    $width = 1 if $width < 1;

    my $val    = $self->{value};
    my $cursor = $self->{cursor};
    my $len    = length($val);
    my $vo     = $self->{view_offset} // 0;

    # If the whole value now fits within $width, there is never a reason
    # to hide any of it -- reset to no scroll unconditionally rather than
    # trusting a cached view_offset from a previous call. view_offset is
    # sticky across calls (see the "Also updates..." doc note above), and
    # the caller-supplied $width can shrink for a single transient render
    # frame -- e.g. the find bar's match-count text grows by "..." for the
    # one frame where the find engine's is_searching flag is briefly true,
    # narrowing input_width just long enough to push a same-width value
    # like "aaa" (cursor at the end) past the scroll-into-view threshold
    # below and bump view_offset up by 1. When the next frame's $width
    # returns to normal (value now fits again), the cursor still fit
    # inside the stale [vo, vo+width) window under the old logic, so
    # nothing corrected view_offset back down, and the widget rendered
    # with its first character permanently scrolled off screen even
    # though $self->{value} itself was never touched (bugs.md P2
    # "Shift+Tab in the find/replace bar drops the last character of BOTH
    # the Find and Replace field values" -- not a Shift+Tab or InputParser
    # bug at all; any transient one-frame narrowing of the field width can
    # trigger this on any InputWidget-backed field). This reset only
    # applies when the full value fits ($len <= $width); it does not
    # touch the deliberate "one empty trailing cell at end-of-value"
    # scroll behavior exercised when the value is longer than the field
    # (see "viewport scrolls to keep cursor visible when at end" below).
    $vo = 0 if $len <= $width;

    # Scroll view_offset so cursor stays within [vo, vo + width - 1]
    if ($cursor < $vo) {
        $vo = $cursor;
    } elsif ($cursor >= $vo + $width) {
        $vo = $cursor - $width + 1;
    }
    $vo = 0 if $vo < 0;
    $self->{view_offset} = $vo;

    my $display_text = substr($val, $vo, $width);

    # Selection bounds clipped to the visible window
    my ($sel_start_in_view, $sel_end_in_view);
    if ($self->has_selection()) {
        my ($s, $e) = $self->selection_range();
        my $sv = $s - $vo;
        my $ev = $e - $vo;
        if ($ev > 0 && $sv < $width) {
            $sel_start_in_view = $sv < 0      ? 0      : $sv;
            $sel_end_in_view   = $ev > $width ? $width : $ev;
        }
    }

    return {
        display_text      => $display_text,
        cursor_in_view    => $cursor - $vo,
        sel_start_in_view => $sel_start_in_view,
        sel_end_in_view   => $sel_end_in_view,
        view_offset       => $vo,
    };
}

# =============================================================================
# Mouse handling
# =============================================================================

# Mouse press / click: place cursor at the given character offset within the
# display area (0-indexed relative to the left edge of the input field).
# Clears any existing selection and starts a potential drag operation.
sub handle_mouse_click {
    my ($self, $char_offset) = @_;
    my $pos = $self->{view_offset} + $char_offset;
    $pos = 0                      if $pos < 0;
    $pos = length($self->{value}) if $pos > length($self->{value});
    $self->{cursor}      = $pos;
    $self->{drag_anchor} = $pos;
    $self->_clear_selection();
}

# Mouse drag update: extend the selection from the original press point to the
# current position.  Call after handle_mouse_click (which sets drag_anchor).
sub handle_mouse_drag_update {
    my ($self, $char_offset) = @_;
    my $anchor = $self->{drag_anchor};
    return unless defined $anchor;

    my $pos = $self->{view_offset} + $char_offset;
    $pos = 0                      if $pos < 0;
    $pos = length($self->{value}) if $pos > length($self->{value});

    $self->{cursor} = $pos;
    if ($pos != $anchor) {
        $self->{sel_start} = $anchor;
        $self->{sel_end}   = $pos;
    } else {
        $self->_clear_selection();
    }
}

# Mouse release: end the drag operation.
sub handle_mouse_drag_end {
    my ($self) = @_;
    $self->{drag_anchor} = undef;
}

# =============================================================================
# Private helpers
# =============================================================================

sub _clear_selection {
    my ($self) = @_;
    $self->{sel_start} = undef;
    $self->{sel_end}   = undef;
}

# Delete the selected range and position cursor at the deletion point.
sub _delete_selection {
    my ($self) = @_;
    my ($s, $e) = $self->selection_range();
    return unless defined $s;
    $self->{value}  = substr($self->{value}, 0, $s) . substr($self->{value}, $e);
    $self->{cursor} = $s;
    $self->_clear_selection();
}

# Extend or begin a selection to $new_pos, moving cursor there.
sub _extend_selection_to {
    my ($self, $new_pos) = @_;
    $self->{sel_start} = $self->{cursor} unless defined $self->{sel_start};
    $self->{sel_end}   = $new_pos;
    $self->{cursor}    = $new_pos;
}

# Position of the word boundary to the left of cursor.
sub _word_left_pos {
    my ($self) = @_;
    my $pos = $self->{cursor};
    my $val = $self->{value};
    $pos-- while $pos > 0 && substr($val, $pos - 1, 1) =~ /\s/;
    $pos-- while $pos > 0 && substr($val, $pos - 1, 1) =~ /\w/;
    return $pos;
}

# Position of the word boundary to the right of cursor.
sub _word_right_pos {
    my ($self) = @_;
    my $pos = $self->{cursor};
    my $val = $self->{value};
    my $len = length($val);
    $pos++ while $pos < $len && substr($val, $pos, 1) =~ /\s/;
    $pos++ while $pos < $len && substr($val, $pos, 1) =~ /\w/;
    return $pos;
}

# =============================================================================
# Event handling
# =============================================================================

# Handle an input event. Returns 1 if the event was consumed, 0 if not.
# Pass a scalar reference as $clipboard_ref to enable cut/copy/paste.
sub handle_event {
    my ($self, $event, $clipboard_ref) = @_;
    my $type = $event->{type} // '';
    return $self->_handle_key($event, $clipboard_ref)  if $type eq 'key';
    return $self->_handle_char($event, $clipboard_ref) if $type eq 'char';
    return 0;
}

sub _handle_key {
    my ($self, $event, $clipboard_ref) = @_;
    my $key   = $event->{key};
    my $shift = Zepto::InputParser::has_modifier($event, 'shift');
    my $alt   = Zepto::InputParser::has_modifier($event, 'alt');
    my $len   = length($self->{value});

    if ($key eq 'left') {
        if ($alt) {
            my $new_pos = $self->_word_left_pos();
            if ($shift) { $self->_extend_selection_to($new_pos); }
            else        { $self->{cursor} = $new_pos; $self->_clear_selection(); }
        }
        elsif ($shift) {
            my $new_pos = $self->{cursor} > 0 ? $self->{cursor} - 1 : 0;
            $self->_extend_selection_to($new_pos);
        }
        elsif ($self->has_selection()) {
            my ($s) = $self->selection_range();
            $self->{cursor} = $s;
            $self->_clear_selection();
        }
        else {
            $self->{cursor}-- if $self->{cursor} > 0;
        }
        return 1;
    }

    elsif ($key eq 'right') {
        if ($alt) {
            my $new_pos = $self->_word_right_pos();
            if ($shift) { $self->_extend_selection_to($new_pos); }
            else        { $self->{cursor} = $new_pos; $self->_clear_selection(); }
        }
        elsif ($shift) {
            my $new_pos = $self->{cursor} < $len ? $self->{cursor} + 1 : $len;
            $self->_extend_selection_to($new_pos);
        }
        elsif ($self->has_selection()) {
            my (undef, $e) = $self->selection_range();
            $self->{cursor} = $e;
            $self->_clear_selection();
        }
        else {
            $self->{cursor}++ if $self->{cursor} < $len;
        }
        return 1;
    }

    elsif ($key eq 'home') {
        if ($shift) { $self->_extend_selection_to(0); }
        else        { $self->{cursor} = 0; $self->_clear_selection(); }
        return 1;
    }

    elsif ($key eq 'end') {
        if ($shift) { $self->_extend_selection_to($len); }
        else        { $self->{cursor} = $len; $self->_clear_selection(); }
        return 1;
    }

    elsif ($key eq 'backspace') {
        if    ($self->has_selection()) { $self->_delete_selection(); }
        elsif ($self->{cursor} > 0) {
            my $pos = $self->{cursor};
            $self->{value} = substr($self->{value}, 0, $pos - 1) . substr($self->{value}, $pos);
            $self->{cursor}--;
        }
        return 1;
    }

    elsif ($key eq 'delete') {
        if    ($self->has_selection()) { $self->_delete_selection(); }
        elsif ($self->{cursor} < $len) {
            my $pos = $self->{cursor};
            $self->{value} = substr($self->{value}, 0, $pos) . substr($self->{value}, $pos + 1);
        }
        return 1;
    }

    return 0;  # enter, escape, tab, up, down, etc. — caller handles
}

sub _handle_char {
    my ($self, $event, $clipboard_ref) = @_;
    my $char = $event->{char};
    my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');
    my $alt  = Zepto::InputParser::has_modifier($event, 'alt');

    return 0 if $alt;  # Alt+char not handled by widget

    if ($ctrl) {
        my $lc = lc($char);

        if ($lc eq 'a') {
            # Select all
            $self->{sel_start} = 0;
            $self->{sel_end}   = length($self->{value});
            $self->{cursor}    = length($self->{value});
            return 1;
        }

        if ($lc eq 'x' && $clipboard_ref) {
            # Cut: only acts when there is a selection
            if ($self->has_selection()) {
                $$clipboard_ref = $self->selected_text();
                $self->_delete_selection();
            }
            return 1;
        }

        if ($lc eq 'c' && $clipboard_ref) {
            # Copy: only acts when there is a selection
            $$clipboard_ref = $self->selected_text() if $self->has_selection();
            return 1;
        }

        if ($lc eq 'v' && $clipboard_ref) {
            # Paste: inserts clipboard at cursor, replacing any selection
            my $text = $$clipboard_ref // '';
            if (length($text)) {
                $self->_delete_selection() if $self->has_selection();
                my $pos = $self->{cursor};
                $self->{value}  = substr($self->{value}, 0, $pos) . $text . substr($self->{value}, $pos);
                $self->{cursor} += length($text);
            }
            return 1;
        }

        return 0;  # Other ctrl chars: not handled by widget
    }

    # Printable char: insert at cursor, replacing any selection
    $self->_delete_selection() if $self->has_selection();
    my $pos = $self->{cursor};
    $self->{value}  = substr($self->{value}, 0, $pos) . $char . substr($self->{value}, $pos);
    $self->{cursor}++;
    return 1;
}

1;
