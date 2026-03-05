package Zepto::Renderer;
# =============================================================================
# Renderer: Pure function to convert view state to terminal escape sequences
# =============================================================================
#
# The renderer takes:
#   - Document content
#   - View state (cursor, selection, scroll)
#   - UI state (menus, dialogs)
#   - Theme
#   - Terminal size
#
# And produces a string of ANSI escape sequences that, when printed, draws
# the complete editor UI.
#
# This is a pure function with no side effects - perfect for testing.
# =============================================================================

use strict;
use warnings;
use utf8;
use Zepto::Chars;
use Zepto::CommandRegistry;
use Zepto::FileTree;
use Zepto::Minimap;

# Escape sequences
use constant {
    ESC         => "\x1b",
    CSI         => "\x1b[",
    CURSOR_HOME => "\x1b[H",
    CLEAR_SCREEN => "\x1b[2J",
    CLEAR_LINE  => "\x1b[K",
    HIDE_CURSOR => "\x1b[?25l",
    SHOW_CURSOR => "\x1b[?25h",

    # Cursor shapes (DECSCUSR)
    CURSOR_BLOCK          => "\x1b[2 q",  # Steady block
    CURSOR_BLOCK_BLINK    => "\x1b[1 q",  # Blinking block
    CURSOR_UNDERLINE      => "\x1b[4 q",  # Steady underline
    CURSOR_UNDERLINE_BLINK => "\x1b[3 q", # Blinking underline
    CURSOR_BAR            => "\x1b[6 q",  # Steady bar (thin vertical line)
    CURSOR_BAR_BLINK      => "\x1b[5 q",  # Blinking bar

    # OSC 12 - Set cursor color (supported by xterm, iTerm2, Kitty, etc.)
    # Format: OSC 12 ; color ST  (using ESC \ as String Terminator)
    CURSOR_COLOR_PREFIX => "\x1b]12;",
    CURSOR_COLOR_SUFFIX => "\x1b\\",
    RESET       => "\x1b[0m",
    BOLD        => "\x1b[1m",
    ATTR_RESET  => "\x1b[22;23;24;29m",  # Reset bold(22), italic(23), underline(24), strikethrough(29)
};

# Box-drawing characters (Unicode)
use constant {
    BOX_HORIZONTAL     => "\x{2500}",  # ─
    BOX_VERTICAL       => "\x{2502}",  # │
    BOX_TOP_LEFT       => "\x{250C}",  # ┌
    BOX_TOP_RIGHT      => "\x{2510}",  # ┐
    BOX_BOTTOM_LEFT    => "\x{2514}",  # └
    BOX_BOTTOM_RIGHT   => "\x{2518}",  # ┘
    BOX_VERTICAL_RIGHT => "\x{251C}",  # ├
    BOX_VERTICAL_LEFT  => "\x{2524}",  # ┤
};

# UI dimensions
use constant {
    DEFAULT_ROWS       => 24,
    DEFAULT_COLS       => 80,
    MIN_GUTTER_WIDTH   => 4,
    MIN_TEXT_WIDTH     => 10,
    DIALOG_WIDTH       => 50,
    DIALOG_HEIGHT      => 5,
    MINIMAP_WIDTH         => Zepto::Minimap::MINIMAP_TOTAL_WIDTH,
    TREE_INDENT_PER_LEVEL => Zepto::FileTree::INDENT_PER_LEVEL,
    TREE_MAX_INDENT       => Zepto::FileTree::MAX_INDENT,
};


# Tab width for visual rendering
use constant TAB_WIDTH => 4;

# Terminal display width of a single character.
# Returns 2 for wide chars (CJK, emoji), 0 for control/combining, 1 otherwise.
# Based on Unicode East Asian Width property (EAW=W or F only).
sub _char_display_width {
    my $ord = ord($_[0]);
    return 0 if $ord < 0x20;       # control chars
    return 1 if $ord < 0x1100;     # ASCII, Latin, Cyrillic, etc.
    return 2 if ($ord >= 0x1100 && $ord <= 0x115F)    # Hangul Jamo
             # Misc Technical — only the EAW=W characters
             || $ord == 0x231A || $ord == 0x231B       # ⌚⌛
             || $ord == 0x2329 || $ord == 0x232A       # 〈〉
             || ($ord >= 0x23E9 && $ord <= 0x23EC)     # ⏩⏪⏫⏬
             || $ord == 0x23F0                          # ⏰
             || $ord == 0x23F3                          # ⏳
             # Misc Symbols / Dingbats — only the EAW=W characters
             || $ord == 0x2614 || $ord == 0x2615       # ☔☕
             || ($ord >= 0x2630 && $ord <= 0x2637)     # ☰-☷ trigrams
             || ($ord >= 0x2648 && $ord <= 0x2653)     # ♈-♓ zodiac
             || $ord == 0x267F                          # ♿
             || ($ord >= 0x268A && $ord <= 0x268F)     # ⚊-⚏ monograms/digrams
             || $ord == 0x2693                          # ⚓
             || $ord == 0x26A1                          # ⚡
             || $ord == 0x26AA || $ord == 0x26AB       # ⚪⚫
             || $ord == 0x26BD || $ord == 0x26BE       # ⚽⚾
             || $ord == 0x26C4 || $ord == 0x26C5       # ⛄⛅
             || $ord == 0x26CE                          # ⛎
             || $ord == 0x26D4                          # ⛔
             || $ord == 0x26EA                          # ⛪
             || $ord == 0x26F2 || $ord == 0x26F3       # ⛲⛳
             || $ord == 0x26F5                          # ⛵
             || $ord == 0x26FA                          # ⛺
             || $ord == 0x26FD                          # ⛽
             || $ord == 0x2705                          # ✅
             || $ord == 0x270A || $ord == 0x270B       # ✊✋
             || $ord == 0x2728                          # ✨
             || $ord == 0x274C                          # ❌
             || $ord == 0x274E                          # ❎
             || ($ord >= 0x2753 && $ord <= 0x2755)     # ❓❔❕
             || $ord == 0x2757                          # ❗
             || ($ord >= 0x2795 && $ord <= 0x2797)     # ➕➖➗
             || $ord == 0x27B0                          # ➰
             || $ord == 0x27BF                          # ➿
             # Stars — only EAW=W
             || $ord == 0x2B50                          # ⭐
             || $ord == 0x2B55                          # ⭕
             # CJK and East Asian ranges (broadly wide)
             || ($ord >= 0x2E80 && $ord <= 0x303E)    # CJK Radicals
             || ($ord >= 0x3040 && $ord <= 0x33BF)    # Japanese
             || ($ord >= 0x3400 && $ord <= 0x4DBF)    # CJK Extension A
             || ($ord >= 0x4E00 && $ord <= 0x9FFF)    # CJK Unified
             || ($ord >= 0xAC00 && $ord <= 0xD7AF)    # Hangul Syllables
             || ($ord >= 0xF900 && $ord <= 0xFAFF)    # CJK Compatibility
             || ($ord >= 0xFE30 && $ord <= 0xFE6F)    # CJK Compatibility Forms
             || ($ord >= 0xFF01 && $ord <= 0xFF60)    # Fullwidth Forms
             || ($ord >= 0xFFE0 && $ord <= 0xFFE6)    # Fullwidth Signs
             || ($ord >= 0x1F000 && $ord <= 0x1FFFF)  # Emoji, Mahjong, etc.
             || ($ord >= 0x20000 && $ord <= 0x2FFFF); # CJK Extension B+
    return 1;
}

# Display width of a string (sum of character display widths)
sub _display_width {
    my ($str) = @_;
    my $w = 0;
    for my $i (0 .. length($str) - 1) {
        $w += _char_display_width(substr($str, $i, 1));
    }
    return $w;
}

# Truncate string to fit within $max_width terminal columns.
# Returns ($truncated_string, $display_width_used).
sub _truncate_to_display_width {
    my ($str, $max_width) = @_;
    my $w = 0;
    for my $i (0 .. length($str) - 1) {
        my $cw = _char_display_width(substr($str, $i, 1));
        if ($w + $cw > $max_width) {
            return (substr($str, 0, $i), $w);
        }
        $w += $cw;
    }
    return ($str, $w);
}

# Expand tabs in a string to spaces, respecting tab stops
# Also returns a mapping from original char positions to visual positions
# Returns: ($expanded_string, \@char_to_visual)
# @char_to_visual[i] = visual column where character i starts
sub _expand_tabs {
    my ($text) = @_;
    return ('', []) unless defined $text && length($text) > 0;

    my $expanded = '';
    my @char_to_visual;
    my $visual_col = 0;

    for my $i (0 .. length($text) - 1) {
        my $char = substr($text, $i, 1);
        push @char_to_visual, $visual_col;

        if ($char eq "\t") {
            # Expand to next tab stop
            my $spaces = TAB_WIDTH - ($visual_col % TAB_WIDTH);
            $expanded .= ' ' x $spaces;
            $visual_col += $spaces;
        } else {
            $expanded .= $char;
            $visual_col += _char_display_width($char);
        }
    }

    return ($expanded, \@char_to_visual);
}

# Convert a character position to visual column
sub _char_to_visual_col {
    my ($text, $char_pos) = @_;
    return 0 unless defined $text && $char_pos > 0;

    my $visual_col = 0;
    my $len = length($text);

    # Walk through actual characters (tabs expand)
    my $walk = $char_pos < $len ? $char_pos : $len;
    for my $i (0 .. $walk - 1) {
        my $char = substr($text, $i, 1);
        if ($char eq "\t") {
            $visual_col += TAB_WIDTH - ($visual_col % TAB_WIDTH);
        } else {
            $visual_col++;
        }
    }

    # Virtual whitespace: positions past line end are 1 visual col each
    if ($char_pos > $len) {
        $visual_col += $char_pos - $len;
    }

    return $visual_col;
}

# Convert a visual/display column to character position in text
# Returns the character index where the visual column falls
# If visual_col falls within a tab's expanded space, returns the tab's position
sub visual_to_char_col {
    my ($text, $visual_col) = @_;
    return 0 unless defined $text && length($text) > 0;
    return 0 if $visual_col <= 0;

    my $current_visual = 0;
    my $len = length($text);

    for my $i (0 .. $len - 1) {
        my $char = substr($text, $i, 1);
        my $char_width;

        if ($char eq "\t") {
            $char_width = TAB_WIDTH - ($current_visual % TAB_WIDTH);
        } else {
            $char_width = 1;
        }

        # If the target visual column falls within this character's display width,
        # return this character's position
        if ($visual_col < $current_visual + $char_width) {
            return $i;
        }

        $current_visual += $char_width;
    }

    # Visual column is beyond end of line — return virtual position
    # (line length + overshoot in virtual whitespace)
    return $len + ($visual_col - $current_visual);
}

# Store and retrieve tab bar button positions for click handling
# Each entry: { start => $x, end => $x, index => $tab_idx, type => 'tab'|'close' }
{
    my $_tab_bar_buttons = [];
    sub _set_tab_bar_buttons { shift; $_tab_bar_buttons = shift; }
    sub get_tab_bar_buttons { return @{$_tab_bar_buttons}; }
}

# Move cursor to row, col (1-indexed)
sub _move_to {
    my ($row, $col) = @_;
    return CSI . $row . ';' . $col . 'H';
}

# Calculate gutter width based on line count
# Exported so Editor.pm can use same calculation for mouse position mapping
# Gutter must fit: VCS indicator (1 col) + cursor line badge (round_left + digits + arrow_right)
# Layout: [vcs][pad][round_left][digits][arrow_right] = 1 + pad + digits + 2
# and normal lines: [vcs][space][right-aligned digits][space]
sub get_gutter_width {
    my ($class, $line_count) = @_;
    $line_count //= 1;  # Default if undef
    my $max_digits = length("$line_count");
    $max_digits = 4 if $max_digits < 4;  # Stable gutter up to 9999 lines
    my $gutter_width = $max_digits + 3;  # +3 for VCS (1) + badge chars (round_left + arrow_right = 2)
    return $gutter_width;
}

# Calculate the minimap width for given parameters.
# Returns 0 if minimap should be hidden.
sub get_minimap_width {
    my ($class, $line_count, $text_height, $cols, $gutter_width, $prefs, $tree_width) = @_;
    $tree_width //= 0;
    return 0 unless $prefs && $prefs->show_minimap();
    return 0 unless $line_count > $text_height;
    my $tentative_text = $cols - $tree_width - $gutter_width - MINIMAP_WIDTH;
    return $tentative_text >= MIN_TEXT_WIDTH ? MINIMAP_WIDTH : 0;
}

# Render the complete editor screen
# Returns a string of escape sequences
sub render {
    my ($class, %args) = @_;

    my $doc         = $args{document};
    my $view        = $args{view};
    my $ui          = $args{ui} // {};
    my $theme       = $args{theme};
    my $prefs       = $args{prefs};
    my $rows        = $args{rows} // DEFAULT_ROWS;
    my $cols        = $args{cols} // DEFAULT_COLS;
    my $message     = $args{message} // '';
    my $message_is_error = $args{message_is_error} // 0;
    my $highlighter = $args{highlighter};  # Optional syntax highlighter
    my $word_wrap_active = $args{word_wrap_active} // ($prefs ? $prefs->word_wrap() : 0);

    # Sync Chars module with prefs
    if ($prefs) {
        Zepto::Chars->set_enabled($prefs->nerd_font());
    }

    # Build per-row buffer for differential rendering
    my @row_buf = ('') x $rows;

    # Calculate layout (no menu bar — tab bar + ruler + text + status)
    my $tab_height = 1;
    my $ruler_height = 1;
    my $status_height = 1;
    my $text_height = $rows - $tab_height - $ruler_height - $status_height;
    $text_height = 1 if $text_height < 1;

    # Calculate gutter width based on line count
    my $line_count = $doc ? $doc->line_count() : 1;
    my $gutter_width = $class->get_gutter_width($line_count);

    # Calculate tree panel width first (tree has higher priority than minimap)
    my $tree = $ui->{file_tree};
    my $tree_width = 0;
    if ($tree && $tree->panel_width() > 0) {
        my $tw = $tree->panel_width() + 1;  # +1 for border column
        my $remaining = $cols - $tw - $gutter_width;
        if ($remaining >= MIN_TEXT_WIDTH) {
            $tree_width = $tw;
        }
    }

    # Determine minimap width (drops before file tree at narrow widths)
    my $show_minimap = $prefs && $prefs->show_minimap();
    my $minimap_width = 0;
    if ($show_minimap && $doc && $line_count > $text_height) {
        my $tentative_text = $cols - $tree_width - $gutter_width - MINIMAP_WIDTH;
        if ($tentative_text >= MIN_TEXT_WIDTH) {
            $minimap_width = MINIMAP_WIDTH;
        }
    }

    my $text_width = $cols - $tree_width - $gutter_width - $minimap_width;
    $text_width = MIN_TEXT_WIDTH if $text_width < MIN_TEXT_WIDTH;

    # Render tree panel (left side, from row 1 to row N-1)
    if ($tree_width > 0 && $tree) {
        my $tree_rows = $class->_render_tree_panel(
            $tree, $rows - $status_height, $theme, $tree_width, $ui
        );
        for my $i (0 .. $#$tree_rows) {
            $row_buf[$i] .= $tree_rows->[$i];
        }
    }

    # Render tab bar (row 1 = index 0)
    $row_buf[0] .= _move_to(1, $tree_width + 1)
        . $class->_render_tab_bar($theme, $cols, $ui, $tree_width);

    # Render ruler (row 2 = index 1)
    $row_buf[1] .= _move_to(2, $tree_width + 1)
        . $class->_render_ruler_bar(
            $theme, $cols, $gutter_width, $view, $doc, $tree_width, $ui
        );

    # Render text area (rows 3..N-1 = index 2..N-2)
    my $text_rows = $class->_render_text_area(
        $doc, $view, $theme,
        $text_height, $text_width, $gutter_width, $highlighter,
        $ui->{find_mode}, $minimap_width, $tree_width
    );
    for my $i (0 .. $#$text_rows) {
        $row_buf[$i + 2] .= $text_rows->[$i];
    }

    # Render status bar (last row = index N-1)
    $row_buf[$rows - 1] .= _move_to($rows, 1);
    if ($ui->{prompt}) {
        $row_buf[$rows - 1] .= $class->_render_prompt(
            $theme, $ui->{prompt}, $cols, $rows
        );
    } elsif ($ui->{find_mode}) {
        $row_buf[$rows - 1] .= $class->_render_find_bar(
            $theme, $ui->{find_mode}, $cols
        );
    } elsif ($ui->{footer_input}) {
        $row_buf[$rows - 1] .= $class->_render_footer_input(
            $theme, $ui->{footer_input}, $cols
        );
    } else {
        $row_buf[$rows - 1] .= $class->_render_context_status_bar(
            $doc, $view, $theme, $cols, $message, $message_is_error, $ui, $word_wrap_active
        );
    }

    # Render dialog overlay (writes to the rows it occupies)
    if ($ui->{dialog}) {
        my $dialog_output = $class->_render_dialog(
            $theme, $ui->{dialog}, $rows, $cols
        );
        $class->_merge_into_rows(\@row_buf, $dialog_output, $rows);
    }

    # Render command palette overlay
    if ($ui->{palette}) {
        my $palette_output = $class->_render_command_palette(
            $theme, $ui->{palette}, $rows, $cols
        );
        $class->_merge_into_rows(\@row_buf, $palette_output, $rows);
    }

    # Build cursor positioning sequence (separate from row content)
    my $cursor_seq = '';
    if ($ui->{palette}) {
        # Position cursor in palette filter input
        # MUST match dimensions in _render_command_palette exactly
        my $palette = $ui->{palette};
        my $pal_width = $cols - 4;
        if ($cols >= 120) {
            $pal_width = 80 if $pal_width > 80;
        } else {
            $pal_width = 60 if $pal_width > 60;
        }
        $pal_width = 30 if $pal_width < 30;
        my $pal_x = int(($cols - $pal_width) / 2);
        $pal_x = 1 if $pal_x < 1;
        my $query_cursor_in_view;
        if (my $w = $palette->{palette_widget}) {
            my $input_area = $pal_width - 6;  # same formula as _render_command_palette
            my $vp = $w->viewport($input_area);
            $query_cursor_in_view = $vp->{cursor_in_view};
        } else {
            $query_cursor_in_view = $palette->{query_cursor} // length($palette->{query} // '');
        }
        # Compute palette height to match _render_command_palette
        my $max_items = $rows - 6;
        $max_items = 5 if $max_items < 5;
        $max_items = 30 if $max_items > 30;
        my $pal_height = 3 + $max_items + 1;
        # Filter input is on row 2 of palette (y_start + 1), starting at x + 4 (box_v + space + icon + space)
        my $pal_y = int(($rows - $pal_height) / 2);
        $pal_y = 2 if $pal_y < 2;
        $cursor_seq .= _move_to($pal_y + 1, $pal_x + 4 + $query_cursor_in_view);
        $cursor_seq .= SHOW_CURSOR;
    } elsif ($ui->{dialog}) {
        # Position cursor in dialog input field
        my $dialog = $ui->{dialog};
        my $dialog_width = DIALOG_WIDTH;
        $dialog_width = $cols - 4 if $dialog_width > $cols - 4;
        my $dx = int(($cols - $dialog_width) / 2);
        $dx = 1 if $dx < 1;
        my $dy = int(($rows - DIALOG_HEIGHT) / 2);
        $dy = 1 if $dy < 1;
        my $cursor_pos = $dialog->{cursor} // length($dialog->{value} // '');
        my $cursor_x = $dx + 2 + $cursor_pos;
        if ($cursor_x > $dx + $dialog_width - 4) {
            $cursor_x = $dx + $dialog_width - 4;
        }
        $cursor_seq .= _move_to($dy + 3, $cursor_x);
        $cursor_seq .= SHOW_CURSOR;
    } elsif ($ui->{footer_input}) {
        # Position cursor in footer input field
        my $input      = $ui->{footer_input};
        my $input_id   = $input->{id} // '';
        my $prompt_len;
        my $input_width;
        if ($input_id eq 'goto_line') {
            my $cursor_icon = Zepto::Chars->get('cursor_pos');
            $prompt_len = length(" $cursor_icon ");
            $input_width = 10;
        } else {
            $prompt_len = length($input->{prompt} // '') + 2;  # +2 for leading/trailing space
            if ($input->{wide}) {
                my $hint = $input->{hint} // '';
                my $hint_str = $hint ? " ($hint)" : '';
                $input_width = $cols - $prompt_len - length($hint_str) - 2;
                $input_width = 20 if $input_width < 20;
            } else {
                $input_width = 12;
            }
        }
        my $cursor_in_view;
        if ($input->{widget}) {
            my $vp = $input->{widget}->viewport($input_width);
            $cursor_in_view = $vp->{cursor_in_view};
        } else {
            $cursor_in_view = $input->{cursor} // 0;
        }
        $cursor_seq .= _move_to($rows, $prompt_len + $cursor_in_view + 1);
        $cursor_seq .= SHOW_CURSOR;
    } elsif ($ui->{find_mode}) {
        # Position cursor in find or replace input field based on focus
        my $find = $ui->{find_mode};
        my $focus = $find->{focus} // 'find';
        my $value = $find->{value} // '';
        my $replace_value = $find->{replace_value} // '';

        # Calculate input_width using same formula as _render_find_bar
        my $match_count = $find->{match_count} // 0;
        my $current = $find->{current} // 0;
        my $is_searching = $find->{is_searching} // 0;
        my $is_replacing = $find->{is_replacing} // 0;
        my $replace_progress = $find->{replace_progress} // 0;
        my $replace_total = $find->{replace_total} // 0;
        my $match_text;
        if ($is_replacing) {
            $match_text = "Replacing $replace_progress/$replace_total...";
        } elsif ($match_count == 0) {
            $match_text = length($value) ? 'No matches' : '';
        } else {
            $match_text = ($current + 1) . ' of ' . $match_count;
            $match_text .= '...' if $is_searching;
        }
        # Account for capture hint width (must match _render_find_bar)
        my $capture_count = $find->{capture_count} // 0;
        my $regex_on = $find->{regex} // 0;
        my $capture_hint = '';
        if ($regex_on) {
            $capture_hint = '$0';
            for my $i (1 .. $capture_count) {
                $capture_hint .= " \$$i";
            }
        }
        my $capture_hint_width = length($capture_hint) ? length($capture_hint) + 1 : 0;
        my $right_side_width = 45 + length($match_text) + $capture_hint_width;
        my $available = $cols - 2 - 5 - 1 - 8 - 1 - $right_side_width;
        my $input_width = int($available / 2);
        $input_width = 8 if $input_width < 8;
        $input_width = 40 if $input_width > 40;

        if ($focus eq 'replace') {
            my $cursor_in_field;
            if (my $w = $find->{replace_widget}) {
                my $vp = $w->viewport($input_width);
                $cursor_in_field = $vp->{cursor_in_view};
            } else {
                my $cursor_pos    = $find->{replace_cursor} // 0;
                my $display_offset = length($replace_value) > $input_width
                    ? length($replace_value) - $input_width : 0;
                $cursor_in_field  = $cursor_pos - $display_offset;
                $cursor_in_field  = 0           if $cursor_in_field < 0;
                $cursor_in_field  = $input_width if $cursor_in_field > $input_width;
            }
            # Replace field position: " Find:" (6) + input_width + " Replace:" (9)
            my $replace_start = 1 + 5 + $input_width + 1 + 8;
            $cursor_seq .= _move_to($rows, $replace_start + $cursor_in_field + 1);
        } else {
            my $cursor_in_field;
            if (my $w = $find->{find_widget}) {
                my $vp = $w->viewport($input_width);
                $cursor_in_field = $vp->{cursor_in_view};
            } else {
                my $cursor_pos    = $find->{cursor} // 0;
                my $display_offset = length($value) > $input_width
                    ? length($value) - $input_width : 0;
                $cursor_in_field  = $cursor_pos - $display_offset;
                $cursor_in_field  = 0           if $cursor_in_field < 0;
                $cursor_in_field  = $input_width if $cursor_in_field > $input_width;
            }
            # Find field starts at column 7 (" Find:")
            my $label_len = 6;  # " Find:"
            $cursor_seq .= _move_to($rows, $label_len + $cursor_in_field + 1);
        }
        $cursor_seq .= SHOW_CURSOR;
    } elsif ($ui->{prompt}) {
        # Hide cursor during prompt - no text input
        $cursor_seq .= HIDE_CURSOR;
    } elsif ($ui->{file_tree} && $ui->{file_tree}->focused()) {
        # Tree is focused — show cursor in search bar (always row 2, above stickies)
        if ($ui->{file_tree}->filter_active()) {
            my $filter_len = length($ui->{file_tree}->filter_query() // '');
            my $prefix_len = 3;  # " {icon} " = 3 visible chars
            my $panel_w = $tree_width > 0 ? $tree_width - 1 : 0;  # subtract border
            my $max_query = $panel_w - $prefix_len;
            my $visible_cursor = ($max_query > 0 && $filter_len > $max_query)
                ? $max_query : $filter_len;
            $cursor_seq .= _move_to(1, $prefix_len + $visible_cursor + 1);
            $cursor_seq .= SHOW_CURSOR;
        } else {
            $cursor_seq .= HIDE_CURSOR;
        }
    } elsif ($view && $doc) {
        # Position terminal cursor for editing
        my ($cursor_row, $cursor_col) = $class->_cursor_screen_pos(
            $view, $gutter_width, $doc, $tree_width
        );
        $cursor_seq .= _move_to($cursor_row, $cursor_col);
        $cursor_seq .= SHOW_CURSOR;
    }

    return {
        rows       => \@row_buf,
        cursor_seq => $cursor_seq,
    };
}

# Backward-compatible render that returns a monolithic string.
# Used by tests; Editor.pm uses render() directly for differential output.
sub render_string {
    my ($class, %args) = @_;
    my $frame = $class->render(%args);
    return HIDE_CURSOR . CURSOR_HOME . join('', @{$frame->{rows}}) . $frame->{cursor_seq};
}

# Parse a multi-row output string and merge segments into the per-row buffer.
# Each segment starts with _move_to(\x1b[ROW;COLH) and is assigned to that row.
sub _merge_into_rows {
    my ($class, $row_buf, $str, $max_rows) = @_;
    return unless length($str);
    # Split at the start of each _move_to sequence, keeping the sequence with its content
    my @parts = split(/(?=\x1b\[\d+;\d+H)/, $str);
    for my $part (@parts) {
        next unless length($part);
        if ($part =~ /^\x1b\[(\d+);\d+H/) {
            my $row_idx = $1 - 1;  # Convert 1-indexed terminal row to 0-indexed
            $row_buf->[$row_idx] .= $part if $row_idx >= 0 && $row_idx < $max_rows;
        }
    }
}

# Render the tab bar showing open file tabs
sub _render_tab_bar {
    my ($class, $theme, $cols, $ui, $tree_width) = @_;
    $tree_width //= 0;

    my $output = '';

    my $tab_cols = $cols - $tree_width;  # available width for tabs
    my $tabs = $ui->{tabs} // [];
    my $active_idx = $ui->{active_tab_index} // 0;
    my $tab_manager = $ui->{tab_manager};

    # Geometric triangle edges for tab shape:
    # ◢ (U+25E2) lower-right triangle: fg fills lower-right → left edge of tab
    # ◣ (U+25E3) lower-left triangle: fg fills lower-left → right edge of tab
    my $TAB_LEFT  = "\x{25e2}";  # ◢
    my $TAB_RIGHT = "\x{25e3}";  # ◣
    my $close_char = "\x{00d7}";  # × (multiplication sign, reliable single-width)
    my $modified_char = "\x{25cf}";  # ● (filled circle)

    my $LEADING_SPACE = 1;

    # --- Pre-calculate per-tab widths with full names ---
    my @tab_info;
    my $total_width = $LEADING_SPACE;
    for my $i (0 .. $#$tabs) {
        my $tab = $tabs->[$i];
        my $name = $tab->{display_name} // '[untitled]';
        my $is_dirty = $tab->{is_dirty} // 0;
        my $has_vcs_changes = $tab->{has_vcs_changes} // 0;
        my $width = _calc_tab_pill_width($name, $is_dirty, $i);
        $total_width += $width;
        push @tab_info, {
            tab             => $tab,
            orig_name       => $name,
            name            => $name,
            is_dirty        => $is_dirty,
            has_vcs_changes => $has_vcs_changes,
            width           => $width,
            index           => $i,
        };
    }

    # --- Handle overflow ---
    my $first_visible = 0;
    my $last_visible = $#tab_info;
    my $show_left_arrow = 0;
    my $show_right_arrow = 0;

    if ($total_width > $tab_cols && @tab_info > 1) {
        # Phase 1: Try progressive name truncation
        _truncate_tab_names(\@tab_info, $tab_cols - $LEADING_SPACE);

        $total_width = $LEADING_SPACE;
        $total_width += $_->{width} for @tab_info;
    }

    if ($total_width > $tab_cols && @tab_info > 1) {
        # Phase 2: Scroll-based subset rendering
        my $left_arrow_width = 2;
        my $right_arrow_width = 2;

        ($first_visible, $last_visible) = _calc_visible_tab_range(
            \@tab_info, $active_idx, $tab_cols - $LEADING_SPACE,
            $left_arrow_width, $right_arrow_width,
        );

        $show_left_arrow = ($first_visible > 0);
        $show_right_arrow = ($last_visible < $#tab_info);

        if ($tab_manager) {
            $tab_manager->set_tab_scroll_offset($first_visible);
        }
    }

    # --- Render tab bar ---
    my $bar_bg = $theme->color('tab_bar_bg');

    # Baseline underline runs across entire row, except under active tab body.
    # SGR 58 sets underline color independently of fg.
    my $ul_color = $theme->color('tab_baseline_ul');
    my $UL_ON  = "\e[4m" . $ul_color;
    my $UL_OFF = "\e[24m";

    # Start row with underline enabled
    $output .= $bar_bg . $UL_ON;

    my $x = 0;
    my @buttons;

    # Leading space (underlined)
    $output .= ' ';
    $x++;

    # Left scroll indicator (clickable, underlined)
    if ($show_left_arrow) {
        my $arrow = Zepto::Chars->enabled() ? "\x{25c2}" : '<';  # ◂ or <
        my $arrow_start_x = $x;
        $output .= $theme->color('tab_inactive_fg') . $arrow . ' ';
        $x += 2;
        push @buttons, {
            start => $arrow_start_x,
            end   => $x - 1,
            index => 0,
            type  => 'scroll_left',
        };
    }

    for my $vi ($first_visible .. $last_visible) {
        my $info = $tab_info[$vi];
        my $i = $info->{index};
        my $is_active = ($i == $active_idx);

        my $name = $info->{name};
        my $is_dirty = $info->{is_dirty};
        my $has_vcs_changes = $info->{has_vcs_changes};

        my $tab_start_x = $x;

        my $tab_bg = $is_active
            ? $theme->color('tab_active_bg')
            : $theme->color('tab_inactive_bg');
        my $edge_fg = $is_active
            ? $theme->color('tab_active_edge')
            : $theme->color('tab_inactive_edge');

        # Left triangle edge ◢ — underlined (part of bar territory)
        $output .= $bar_bg . $edge_fg . $TAB_LEFT;
        $x++;

        # Tab interior
        my $name_color;
        if ($is_active) {
            $name_color = $theme->color('tab_active_fg');
        } else {
            $name_color = $has_vcs_changes
                ? $theme->color('tab_vcs_fg')
                : $theme->color('tab_inactive_fg');
        }

        # Active tab body: no underline (opens into ruler below)
        # Inactive tab body: underline continues (baseline runs through)
        if ($is_active) {
            $output .= $UL_OFF . $tab_bg . $name_color;
        } else {
            $output .= $tab_bg . $name_color;
        }

        # Space + name
        $output .= " $name";
        $x += 1 + length($name);

        # Dirty indicator
        if ($is_dirty) {
            $output .= ' ';
            $output .= $theme->color('tab_modified_fg');
            $output .= $modified_char;
            $output .= $name_color;
            $x += 2;
        }

        # Shortcut hint for tabs 1-9 (⌥N = Alt+N to switch)
        if ($i < 9) {
            $output .= ' ';
            $output .= $theme->color('tab_shortcut_fg');
            my $hint = "\x{2325}" . ($i + 1);  # ⌥N
            $output .= $hint;
            $output .= $name_color;
            $x += 1 + length($hint);
        }

        # Close button
        $output .= ' ';
        my $close_start_x = $x;
        $output .= $theme->color('tab_close_fg');
        $output .= $close_char;
        $x += 2;

        push @buttons, {
            start => $close_start_x,
            end   => $x - 1,
            index => $i,
            type  => 'close',
        };

        # Right triangle edge ◣ — re-enable underline (back to bar territory)
        if ($is_active) {
            $output .= $UL_ON;
        }
        $output .= $bar_bg . $edge_fg . $TAB_RIGHT;
        $x++;

        push @buttons, {
            start => $tab_start_x,
            end   => $x - 1,
            index => $i,
            type  => 'tab',
        };

        # Gap between tabs (underlined)
        if ($vi < $last_visible) {
            $output .= $bar_bg . ' ';
            $x++;
        }
    }

    # Right scroll indicator (clickable, underlined)
    if ($show_right_arrow) {
        my $arrow = Zepto::Chars->enabled() ? "\x{25b8}" : '>';  # ▸ or >
        my $arrow_start_x = $x;
        $output .= $bar_bg . ' ' . $theme->color('tab_inactive_fg') . $arrow;
        $x += 2;
        push @buttons, {
            start => $arrow_start_x,
            end   => $x - 1,
            index => 0,
            type  => 'scroll_right',
        };
    }

    # Fill remaining space, with right-aligned tab hints if room
    my $remaining = $tab_cols - $x;
    my $hint_close = "\x{2303}W \x{00d7}";  # ⌃W ×
    my $hint_nav   = "\x{2325}, \x{2190}  \x{2325}. \x{2192}";  # ⌥, ←  ⌥. →
    my $hint_full  = "$hint_close  $hint_nav";
    my $hint_width = length($hint_full) + 2;  # +2 for surrounding spaces

    if ($remaining >= $hint_width) {
        my $fill = $remaining - $hint_width;
        $output .= $bar_bg;
        $output .= ' ' x $fill if $fill > 0;
        $output .= ' ' . $theme->color('tab_shortcut_fg') . $hint_full . ' ';
    } elsif ($remaining > 0) {
        $output .= $bar_bg;
        $output .= ' ' x $remaining;
    }
    $output .= $UL_OFF . RESET;

    # Offset button positions by tree_width so mouse clicks map correctly
    if ($tree_width > 0) {
        $_->{start} += $tree_width for @buttons;
        $_->{end}   += $tree_width for @buttons;
    }

    $class->_set_tab_bar_buttons(\@buttons);

    return $output;
}

# Calculate the display width of a tab pill (not counting inter-tab gap)
# Width = left_tri(1) + " name" + [" ●"(2)] + [" ⌥N"(3)] + " ×"(2) + right_tri(1) + gap(1)
sub _calc_tab_pill_width {
    my ($name, $is_dirty, $tab_index) = @_;
    my $w = 1 + 1 + length($name) + 2 + 1 + 1;  # left_tri + space + name + " ×" + right_tri + gap
    $w += 2 if $is_dirty;            # space + ●
    $w += 3 if $tab_index < 9;       # space + ⌥N (2 chars)
    return $w;
}

# Truncate tab names to fit within available width.
# Preserves file extension, truncates stem with "…".
sub _truncate_tab_names {
    my ($tab_info, $avail) = @_;

    my $ELLIPSIS = "\x{2026}";  # …
    my $MIN_STEM = 4;           # Minimum stem chars before ellipsis

    # Calculate current total
    my $total = 0;
    $total += $_->{width} for @$tab_info;
    return if $total <= $avail;

    # Sort indices by name length descending (truncate longest first)
    my @by_len = sort { length($b->{name}) <=> length($a->{name}) } @$tab_info;

    for my $pass (1 .. 20) {  # Safety limit
        last if $total <= $avail;

        # Find the current longest name length
        my $max_len = length($by_len[0]->{name});
        last if $max_len <= $MIN_STEM + 1;  # Can't truncate further

        # Target: truncate to one less than current max, or to fit
        my $excess = $total - $avail;
        my $target_len = $max_len - 1;

        for my $info (@by_len) {
            last if $total <= $avail;
            my $cur_len = length($info->{name});
            next if $cur_len <= $target_len;

            my $orig = $info->{orig_name};
            my ($stem, $ext) = $orig =~ /^(.+?)(\.[^.]+)$/ ? ($1, $2) : ($orig, '');

            my $max_name_len = $target_len;
            $max_name_len = $MIN_STEM + length($ELLIPSIS) + length($ext)
                if $max_name_len < $MIN_STEM + length($ELLIPSIS) + length($ext);

            my $new_name;
            if (length($orig) <= $max_name_len) {
                $new_name = $orig;
            } else {
                my $stem_budget = $max_name_len - length($ELLIPSIS) - length($ext);
                $stem_budget = $MIN_STEM if $stem_budget < $MIN_STEM;
                $new_name = substr($stem, 0, $stem_budget) . $ELLIPSIS . $ext;
            }

            my $old_width = $info->{width};
            $info->{name} = $new_name;
            $info->{width} = _calc_tab_pill_width($new_name, $info->{is_dirty}, $info->{index});
            $total -= ($old_width - $info->{width});
        }

        # Re-sort by name length
        @by_len = sort { length($b->{name}) <=> length($a->{name}) } @$tab_info;
    }
}

# Determine visible tab range when scrolling is needed.
# Returns ($first_visible, $last_visible) indices.
sub _calc_visible_tab_range {
    my ($tab_info, $active_idx, $avail, $left_arrow_w, $right_arrow_w) = @_;

    my $count = scalar @$tab_info;
    return (0, $count - 1) if $count <= 1;

    # Start by trying to center the active tab
    # Expand outward from active tab, fitting as many tabs as possible
    my $first = $active_idx;
    my $last = $active_idx;
    my $used = $tab_info->[$active_idx]{width};

    # Reserve space for arrows
    my $left_reserve = ($first > 0) ? $left_arrow_w : 0;
    my $right_reserve = ($last < $count - 1) ? $right_arrow_w : 0;

    # Expand alternating left and right
    my $expanded = 1;
    while ($expanded) {
        $expanded = 0;

        # Try expanding right
        if ($last < $count - 1) {
            my $new_right_reserve = ($last + 1 < $count - 1) ? $right_arrow_w : 0;
            my $needed = $used + $tab_info->[$last + 1]{width} + $left_reserve + $new_right_reserve;
            if ($needed <= $avail) {
                $last++;
                $used += $tab_info->[$last]{width};
                $right_reserve = $new_right_reserve;
                $expanded = 1;
            }
        }

        # Try expanding left
        if ($first > 0) {
            my $new_left_reserve = ($first - 1 > 0) ? $left_arrow_w : 0;
            my $needed = $used + $tab_info->[$first - 1]{width} + $new_left_reserve + $right_reserve;
            if ($needed <= $avail) {
                $first--;
                $used += $tab_info->[$first]{width};
                $left_reserve = $new_left_reserve;
                $expanded = 1;
            }
        }
    }

    return ($first, $last);
}

# Render the ruler bar showing column positions
sub _render_ruler_bar {
    my ($class, $theme, $cols, $gutter_width, $view, $doc, $tree_width, $ui) = @_;
    $tree_width //= 0;

    my $output = '';

    # Get cursor position
    my $cursor_line = $view ? $view->cursor_line() : 0;
    my $cursor_col_char = $view ? $view->cursor_col() : 0;
    my $scroll_col = $view ? $view->scroll_col() : 0;

    # Calculate visual cursor column from the cursor line's content
    # This ensures ruler badge matches the crosshair visual position
    my $cursor_line_content = ($doc && $cursor_line < $doc->line_count())
        ? $doc->get_line_content($cursor_line)
        : '';
    my $visual_cursor_col = _char_to_visual_col($cursor_line_content, $cursor_col_char);
    my $cursor_col = $visual_cursor_col + 1;  # 1-indexed for display

    # Visible cursor position (relative to viewport)
    my $visible_cursor = $visual_cursor_col - $scroll_col;

    # In wrap mode, position badge at cursor's visual col within the wrap row
    my $wm = $view ? $view->wrap_map() : undef;
    if ($wm) {
        my ($vrow, $vcol) = $wm->doc_to_visual($cursor_line, $cursor_col_char, $view->cursor_affinity());
        $visible_cursor = $vcol;
    }

    # Start with gutter area (empty, matches gutter width)
    $output .= $theme->color('ruler_bg') . $theme->color('ruler_fg');
    $output .= ' ' x $gutter_width;

    # Calculate ruler width (text area width, excluding tree)
    my $ruler_width = $cols - $tree_width - $gutter_width;

    # Build ruler string: |10      |20      |30 ... (1-indexed columns, marks at multiples of 10)
    my $ruler = '';
    my $mark_interval = 10;
    my $x = 0;

    while ($x < $ruler_width) {
        my $col_num = $scroll_col + $x + 1;  # 1-indexed column number
        # Mark every 10th column (10, 20, 30...)
        if ($col_num % $mark_interval == 0) {
            $ruler .= '|' . $col_num;
            $x += 1 + length("$col_num");
        } else {
            $ruler .= ' ';
            $x++;
        }
    }
    # Pad/truncate to exact width
    $ruler = substr($ruler, 0, $ruler_width);
    $ruler .= ' ' x ($ruler_width - length($ruler)) if length($ruler) < $ruler_width;

    # Calculate cursor badge position and size
    # Badge shows: space + column number + round right
    my $rr = Zepto::Chars->get('round_right');
    my $cursor_str = sprintf("%d", $cursor_col);
    my $badge_width = length($cursor_str) + 2;  # +1 for leading space, +1 for round_right
    my $badge_start = $visible_cursor;
    my $badge_end = $badge_start + $badge_width;

    # Render the ruler, inserting cursor badge at the right position
    # Use explicit index control (no auto-increment in for loop)
    my $i = 0;
    while ($i < $ruler_width) {
        # Check if we're at the cursor badge position
        if ($i == $badge_start && $visible_cursor >= 0 && $badge_end <= $ruler_width) {
            # Render cursor badge: space + number + round right
            $output .= $theme->color('ruler_cursor_bg') . $theme->color('ruler_cursor_fg');
            $output .= ' ' . $cursor_str;
            $output .= $theme->color('ruler_bg') . $theme->color('ruler_cursor_edge') . $rr;
            $output .= $theme->color('ruler_fg');
            # Skip past the badge width in the source ruler
            $i += $badge_width;
        } else {
            # Regular ruler character
            my $ch = substr($ruler, $i, 1);
            if ($ch eq '|') {
                $output .= $theme->color('ruler_mark');
                $output .= $ch;
                $output .= $theme->color('ruler_fg');
            } else {
                $output .= $ch;
            }
            $i++;
        }
    }

    my @ruler_buttons;
    if ($view && $view->column_select()) {
        my $label = " COL ";
        my $label_width = length($label);
        if ($label_width < $cols) {
            my $col_start = $cols - $label_width + 1;
            $output .= _move_to(2, $col_start);
            $output .= $theme->color('column_indicator_bg') . $theme->color('column_indicator_fg');
            $output .= $label;
            push @ruler_buttons, {
                x_start => $col_start,
                x_end   => $col_start + $label_width - 1,
                action  => 'toggle_column_mode',
            };
        }
    }
    $class->_set_ruler_buttons(\@ruler_buttons);

    $output .= CLEAR_LINE;
    $output .= RESET;

    return $output;
}

# Render the text area with line numbers
sub _render_text_area {
    my ($class, $doc, $view, $theme, $height, $width, $gutter_width, $highlighter, $find_mode, $minimap_width, $tree_width) = @_;
    $minimap_width //= 0;
    $tree_width //= 0;

    my @text_rows;

    return \@text_rows unless $doc && $view;

    my $scroll_line = $view->scroll_line();
    my $visible_start = $scroll_line;
    my $visible_end = $scroll_line + $height;

    # Get LineMap for inline diff expansion
    my $line_map = $view->line_map();
    my $has_expanded = $line_map && $line_map->has_expanded_hunks();

    # Build visible entries from WrapMap, LineMap, or simple doc-line mapping
    my @entries;
    my $wrap_map = $view->wrap_map();
    if ($wrap_map && $has_expanded) {
        # Combined: use LineMap for entry ordering, WrapMap for wrapping
        # Get more raw entries than $height since wrapping will expand them
        my $fetch_count = $height * 3;  # fetch extra — wrapping may expand lines
        my $raw = $line_map->visible_entries($scroll_line, $fetch_count);
        my $wrap_width = $wrap_map->{width};
        my $tab_width = $wrap_map->{tab_width} // 8;
        for my $entry (@$raw) {
            last if @entries >= $height;
            next unless $entry;
            if ($entry->{type} eq 'old') {
                # Wrap old-line content using WrapMap's wrap_line
                my $base_lines = $doc->vcs_base_lines();
                my $line_content = $base_lines ? ($base_lines->[$entry->{base_line}] // '') : '';
                my $segments = $wrap_map->wrap_line($line_content, $wrap_width);
                for my $seg (@$segments) {
                    last if @entries >= $height;
                    push @entries, {
                        %$entry,
                        wrap_index   => $seg->{wrap_index},
                        col_start    => $seg->{col_start},
                        col_end      => $seg->{col_end},
                        vis_start    => $seg->{vis_start},
                        vis_end      => $seg->{vis_end},
                        indent_width => $seg->{indent_width},
                    };
                }
            } else {
                # Doc line: get wrap segments from WrapMap
                my $segs = $wrap_map->segments_for_line($entry->{line});
                if ($segs && @$segs) {
                    for my $seg (@$segs) {
                        last if @entries >= $height;
                        push @entries, {
                            type         => ($seg->{wrap_index} == 0) ? 'doc' : 'wrap_cont',
                            line         => $entry->{line},
                            hunk_idx     => $entry->{hunk_idx},
                            wrap_index   => $seg->{wrap_index},
                            col_start    => $seg->{col_start},
                            col_end      => $seg->{col_end},
                            vis_start    => $seg->{vis_start},
                            vis_end      => $seg->{vis_end},
                            indent_width => $seg->{indent_width},
                        };
                    }
                } else {
                    push @entries, $entry;
                }
            }
        }
        while (@entries < $height) {
            push @entries, undef;
        }
    } elsif ($wrap_map) {
        my $scroll_vrow = $view->scroll_visual_row();
        for my $i (0 .. $height - 1) {
            my $seg = $wrap_map->segment_at_visual_row($scroll_vrow + $i);
            if ($seg) {
                push @entries, {
                    type         => ($seg->{wrap_index} == 0) ? 'doc' : 'wrap_cont',
                    line         => $seg->{doc_line},
                    wrap_index   => $seg->{wrap_index},
                    col_start    => $seg->{col_start},
                    col_end      => $seg->{col_end},
                    vis_start    => $seg->{vis_start},
                    vis_end      => $seg->{vis_end},
                    indent_width => $seg->{indent_width},
                };
            } else {
                push @entries, undef;
            }
        }
        # Update visible_start/visible_end for find match binary search
        $visible_start = $entries[0] ? $entries[0]{line} : $scroll_line;
        my $last_entry = $entries[$#entries];
        $visible_end = $last_entry ? ($last_entry->{line} + 1) : ($scroll_line + $height);
    } elsif ($has_expanded) {
        my $raw = $line_map->visible_entries($scroll_line, $height);
        @entries = @$raw;
        # Pad with undef if fewer entries than height (end of file)
        while (@entries < $height) {
            push @entries, undef;
        }
    } else {
        for my $i (0 .. $height - 1) {
            push @entries, { type => 'doc', line => $scroll_line + $i };
        }
    }

    # Lazily-created base highlighter for old-line syntax highlighting
    my $base_highlighter;

    # Precompute match ranges by line if in find mode (only visible lines)
    # Use viewport_matches for O(viewport) instead of O(all_matches)
    my %line_matches;  # line_num => [{start, end, is_current}, ...]
    my %line_capture_regions;  # line_num => [{start, end, group, is_current}, ...]
    if ($find_mode && $find_mode->{matches} && @{$find_mode->{matches}}) {
        my $matches = $find_mode->{matches};
        my $current = $find_mode->{current} // 0;

        # Find current match line for highlighting
        my $current_line = $matches->[$current]{line} if $current < @$matches;
        my $current_col = $matches->[$current]{col} if $current < @$matches;

        # Compiled regex for extracting capture positions from any match
        my $capture_regex = $find_mode->{capture_regex};
        my $capture_count = $find_mode->{capture_count} // 0;

        # Only iterate visible matches - use binary search to find range
        # Since matches are sorted by (line, col), find first visible
        my $first_visible = 0;
        my $last_visible = $#$matches;

        # Binary search for first match in visible range
        my ($lo, $hi) = (0, $#$matches);
        while ($lo < $hi) {
            my $mid = int(($lo + $hi) / 2);
            if ($matches->[$mid]{line} < $visible_start) {
                $lo = $mid + 1;
            } else {
                $hi = $mid;
            }
        }
        $first_visible = $lo;

        # Process only visible matches
        for my $idx ($first_visible .. $#$matches) {
            my $match = $matches->[$idx];
            my $line = $match->{line};
            last if $line >= $visible_end;  # Past visible range

            my $col = $match->{col};
            my $end_col = $col + $match->{length};

            my $is_current = ($idx == $current);

            $line_matches{$line} //= [];
            push @{$line_matches{$line}}, {
                start => $col,
                end => $end_col,
                is_current => $is_current,
            };

            # Extract capture sub-regions for ALL visible matches
            if ($capture_regex && $capture_count > 0 && $match->{length} > 0) {
                my $line_content = $doc->get_line_content($line);
                my $matched_text = substr($line_content, $col, $match->{length});
                if ($matched_text =~ /$capture_regex/) {
                    $line_capture_regions{$line} //= [];
                    for my $gi (1 .. $#+) {
                        if (defined $-[$gi]) {
                            push @{$line_capture_regions{$line}}, {
                                start      => $col + $-[$gi],
                                end        => $col + $+[$gi],
                                group      => $gi,
                                is_current => $is_current,
                            };
                        }
                    }
                }
            }
        }
    }

    # Also include replaced text positions (shown as current match highlight)
    if ($find_mode && $find_mode->{replaced} && @{$find_mode->{replaced}}) {
        my $replaced = $find_mode->{replaced};
        for my $rep (@$replaced) {
            # Calculate line/col from offset if not cached
            my $line = $rep->{line};
            my $col = $rep->{col};
            if (!defined $line) {
                ($line, $col) = $doc->offset_to_line_col($rep->{offset});
            }
            next if $line < $visible_start || $line >= $visible_end;  # Skip non-visible

            my $end_col = $col + $rep->{length};

            $line_matches{$line} //= [];
            push @{$line_matches{$line}}, {
                start => $col,
                end => $end_col,
                is_current => 1,  # Replaced text shown prominently
            };
        }
    }
    my $scroll_col = $view->scroll_col();
    my $cursor_line = $view->cursor_line();
    my $cursor_col = $view->cursor_col();

    # Calculate the visual cursor column from the cursor line's content
    my $cursor_line_content = $cursor_line < $doc->line_count()
        ? $doc->get_line_content($cursor_line)
        : '';
    my $visual_cursor_col = _char_to_visual_col($cursor_line_content, $cursor_col);

    # Precompute minimap data (once, before row loop)
    my $minimap_data;
    if ($minimap_width > 0) {
        $minimap_data = Zepto::Minimap->compute(
            document => $doc,
            view     => $view,
            height   => $height,
        );
    }

    # Cache for per-hunk character-level diff highlights
    my %hunk_char_diffs;  # hunk_idx => { old => {base_line => [start, end]}, new => {doc_line => [start, end]} }

    for my $screen_row (0 .. $height - 1) {
        my $entry = $entries[$screen_row];

        # Per-row output buffer (for differential rendering)
        my $output = _move_to($screen_row + 3, $tree_width + 1);

        # Handle old-line entries (expanded hunk base content)
        if ($entry && $entry->{type} eq 'old') {
            # Ensure char-level highlights are computed for this hunk
            my $hunk_idx = $entry->{hunk_idx};
            if (!exists $hunk_char_diffs{$hunk_idx}) {
                my $hunks = $doc->vcs_hunks();
                if ($hunks && $hunk_idx < @$hunks) {
                    my ($old_hl, $new_hl) = $class->_compute_hunk_highlights(
                        $hunks->[$hunk_idx], $doc, $doc->vcs_base_lines()
                    );
                    $hunk_char_diffs{$hunk_idx} = { old => $old_hl, new => $new_hl };
                } else {
                    $hunk_char_diffs{$hunk_idx} = { old => {}, new => {} };
                }
            }
            # Only apply char-level highlights for the first segment of old lines
            my $char_hl = (!$entry->{wrap_index})
                ? $hunk_char_diffs{$hunk_idx}{old}{$entry->{base_line}}
                : undef;
            $output .= $class->_render_old_line_row(
                $doc, $view, $theme, $width, $gutter_width,
                $entry, $highlighter, \$base_highlighter, $char_hl
            );
            $output .= $class->_render_minimap_column($minimap_data, $screen_row, $theme)
                if $minimap_width > 0;
            $output .= CLEAR_LINE;
            $output .= RESET;
            push @text_rows, $output;
            next;
        }

        my $doc_line = $entry ? $entry->{line} : ($scroll_line + $screen_row);
        my $is_cursor_line = ($doc_line == $cursor_line);
        my $is_hunk_line = $entry && defined $entry->{hunk_idx};
        my $is_wrap_cont = $entry && ($entry->{type} // '') eq 'wrap_cont';

        # Wrap continuation gutter: blank line number, ↪ placed before first content char
        # Diff gutter markers extend across all continuation lines
        if ($is_wrap_cont) {
            # Check VCS status for the underlying doc line
            my $chg_status = $doc->vcs_change_status($doc_line);
            my $vcs_char = ' ';
            my $vcs_color = $theme->color('gutter_fg');
            if ($chg_status) {
                if ($chg_status eq 'added') {
                    $vcs_char = Zepto::Chars->get('vcs_added');
                    $vcs_color = $theme->color('vcs_added');
                } elsif ($chg_status eq 'modified') {
                    $vcs_char = Zepto::Chars->get('vcs_modified');
                    $vcs_color = $theme->color('vcs_modified');
                } elsif ($chg_status eq 'modified_whitespace') {
                    $vcs_char = Zepto::Chars->get('vcs_modified');
                    $vcs_color = $theme->color('vcs_modified_whitespace');
                }
            }
            my $gutter_bg = $theme->color('gutter_bg');
            my $indent_w = $entry->{indent_width} // 0;
            if ($indent_w == 0) {
                # No hanging indent: VCS marker + padding + wrap indicator
                $output .= $gutter_bg . $vcs_color . $vcs_char;
                $output .= $theme->color('gutter_fg');
                $output .= ' ' x ($gutter_width - 2);
                $output .= $theme->color('wrap_indicator_fg');
                $output .= Zepto::Chars->get('wrap_indicator');
            } else {
                # Has hanging indent: VCS marker + padding, ↪ goes in content indent area
                $output .= $gutter_bg . $vcs_color . $vcs_char;
                $output .= $theme->color('gutter_fg');
                $output .= ' ' x ($gutter_width - 1);
            }
        }
        # Line number gutter with VCS indicator (single column)
        elsif ($doc_line < $doc->line_count()) {
            my $line_num_str = sprintf("%d", $doc_line + 1);

            # Get VCS indicator for this line (single column)
            # Due to our diff algorithm, deletions never overlap with adds/modifies
            my $del_status = $doc->vcs_deletion_status($doc_line);
            my $chg_status = $doc->vcs_change_status($doc_line);

            my ($vcs_char, $vcs_color);

            if ($chg_status) {
                # Added or modified line
                if ($chg_status eq 'added') {
                    $vcs_char = Zepto::Chars->get('vcs_added');
                    $vcs_color = $theme->color('vcs_added');
                } elsif ($chg_status eq 'modified') {
                    $vcs_char = Zepto::Chars->get('vcs_modified');
                    $vcs_color = $theme->color('vcs_modified');
                } elsif ($chg_status eq 'modified_whitespace') {
                    $vcs_char = Zepto::Chars->get('vcs_modified');
                    $vcs_color = $theme->color('vcs_modified_whitespace');
                }
            } elsif ($del_status) {
                # Deletion marker spans two lines to show the gap where content was removed
                # 'below' = deletion after this line (show ▗ lower quadrant)
                # 'above' = deletion before this line (show ▝ upper quadrant)
                if ($del_status eq 'below') {
                    $vcs_char = Zepto::Chars->get('vcs_del_lower');
                } elsif ($del_status eq 'above') {
                    $vcs_char = Zepto::Chars->get('vcs_del_upper');
                }
                $vcs_color = $theme->color('vcs_deleted');
            }
            $vcs_char //= ' ';
            $vcs_color //= $theme->color('gutter_fg');

            # Gutter background: use diff_new_gutter_bg for hunk lines
            my $gutter_bg = $is_hunk_line
                ? $theme->color('diff_new_gutter_bg')
                : $theme->color('gutter_bg');

            # Override gutter for expanded hunk lines:
            # - Fat block (█) instead of thin (▐) to show expanded state
            # - Added hunks: green gutter; modified hunks: keep yellow
            if ($is_hunk_line) {
                $vcs_char = Zepto::Chars->get('vcs_expanded');
                my $hunks = $doc->vcs_hunks();
                my $h = $hunks->[$entry->{hunk_idx}];
                if ($h && $h->{type} eq 'added') {
                    $vcs_color = $theme->color('vcs_added');
                }
                # Modified hunks keep vcs_modified (yellow) which is already set
            }

            if ($is_cursor_line) {
                # Cursor line: [vcs][pad][rl][space][digits][ar]
                my $rl = Zepto::Chars->get('round_left');
                my $ar = Zepto::Chars->get('arrow_right');

                # VCS indicator first (on gutter background)
                $output .= $gutter_bg . $vcs_color . $vcs_char;

                # Right-align: match the sprintf padding used in normal lines
                # Normal line uses sprintf("%*d", gutter_width - 3, num) which right-aligns
                my $num_width = $gutter_width - 3;  # 1(vcs) + 1(space) + digits + 1(space) = gutter_width
                my $padded_num = sprintf("%*d", $num_width, $doc_line + 1);

                # Badge: rl + padded_num + ar
                $output .= $gutter_bg . $theme->color('ruler_cursor_edge') . $rl;
                $output .= $theme->color('ruler_cursor_bg') . $theme->color('ruler_cursor_fg') . $padded_num;
                # Arrow right: badge color as fg, next area color as bg
                my $next_bg = $is_hunk_line
                    ? $theme->color('diff_new_cursor_bg')
                    : $theme->color('cursor_line_bg');
                $output .= $next_bg . $theme->color('ruler_cursor_edge') . $ar;
            } else {
                # Normal line: [vcs][space][right-aligned digits][space]
                # VCS indicator first
                $output .= $gutter_bg . $vcs_color . $vcs_char;
                # Rest of gutter
                $output .= $gutter_bg . $theme->color('gutter_fg');
                # Use (gutter_width - 3) for digits: total = 1(vcs) + 1(space) + digits + 1(space) = gutter_width
                my $line_num = sprintf("%*d", $gutter_width - 3, $doc_line + 1);
                $output .= ' ' . $line_num . ' ';
            }
        }
        else {
            $output .= $theme->color('gutter_bg') . $theme->color('gutter_fg');
            $output .= ' ' x $gutter_width;
        }

        # Background: cursor+hunk > cursor > hunk > normal
        my $line_bg;
        if ($is_cursor_line && $is_hunk_line) {
            $line_bg = $theme->color('diff_new_cursor_bg');
        } elsif ($is_cursor_line) {
            $line_bg = $theme->color('cursor_line_bg');
        } elsif ($is_hunk_line) {
            $line_bg = $theme->color('diff_new_bg');
        } else {
            $line_bg = $theme->color('bg');
        }
        $output .= $line_bg . $theme->color('fg');

        # Text content
        if ($doc_line < $doc->line_count()) {
            my $line_content = $doc->get_line_content($doc_line);
            my $full_line_content = $line_content;  # Keep full line for tokenization

            # Check for virtual replace preview (shows replaced text without modifying buffer)
            my $preview_data;
            if ($find_mode && $find_mode->{replace_preview} && exists $find_mode->{replace_preview}{$doc_line}) {
                $preview_data = $find_mode->{replace_preview}{$doc_line};
                $line_content = $preview_data->{text};
                $full_line_content = $preview_data->{text};
            }

            # Get syntax tokens for this line (before tab expansion)
            my $tokens = [];
            if ($highlighter) {
                ($tokens) = $highlighter->tokenize_line($full_line_content, $doc_line);
            }

            # Expand tabs in the full line content and get position mapping
            my ($expanded_content, $char_to_visual) = _expand_tabs($full_line_content);

            # Convert token positions from character to visual positions
            my @visual_tokens;
            for my $tok (@$tokens) {
                my $vis_start = $char_to_visual->[$tok->{start}] // 0;
                my $vis_end = $tok->{end} < @$char_to_visual
                    ? $char_to_visual->[$tok->{end}]
                    : length($expanded_content);
                push @visual_tokens, {
                    start => $vis_start,
                    end => $vis_end,
                    type => $tok->{type},
                };
            }

            # Convert find match positions from character to visual positions
            my @visual_matches;
            if ($preview_data && $preview_data->{highlights}) {
                # Use virtual preview highlights (positions already in preview text)
                for my $h (@{$preview_data->{highlights}}) {
                    push @visual_matches, {
                        start => $h->{start},
                        end => $h->{end},
                        is_current => 1,  # All replacements shown prominently
                    };
                }
            } elsif ($line_matches{$doc_line}) {
                for my $m (@{$line_matches{$doc_line}}) {
                    my $vis_start = $char_to_visual->[$m->{start}] // 0;
                    my $vis_end = $m->{end} < @$char_to_visual
                        ? $char_to_visual->[$m->{end}]
                        : length($expanded_content);
                    push @visual_matches, {
                        start => $vis_start,
                        end => $vis_end,
                        is_current => $m->{is_current},
                    };
                }
            }

            # Convert capture sub-regions to visual positions
            my @visual_capture_regions;
            if ($preview_data && $preview_data->{capture_regions} && @{$preview_data->{capture_regions}}) {
                # Preview mode: use capture regions mapped to replacement text
                for my $cr (@{$preview_data->{capture_regions}}) {
                    my $vis_start = $char_to_visual->[$cr->{start}] // 0;
                    my $vis_end = $cr->{end} < @$char_to_visual
                        ? $char_to_visual->[$cr->{end}]
                        : length($expanded_content);
                    push @visual_capture_regions, {
                        start      => $vis_start,
                        end        => $vis_end,
                        group      => $cr->{group},
                        is_current => 1,  # All preview replacements shown prominently
                    };
                }
            } elsif (!$preview_data && $line_capture_regions{$doc_line}) {
                # Normal mode: use capture regions from original match positions
                for my $cr (@{$line_capture_regions{$doc_line}}) {
                    my $vis_start = $char_to_visual->[$cr->{start}] // 0;
                    my $vis_end = $cr->{end} < @$char_to_visual
                        ? $char_to_visual->[$cr->{end}]
                        : length($expanded_content);
                    push @visual_capture_regions, {
                        start      => $vis_start,
                        end        => $vis_end,
                        group      => $cr->{group},
                        is_current => $cr->{is_current},
                    };
                }
            }

            # Determine effective scroll column
            # In wrap mode, each segment is rendered as a slice of the full line
            # using effective_scroll_col = vis_start - indent_width
            my $effective_scroll_col = $scroll_col;
            my $has_wrap_segment = $entry && defined $entry->{wrap_index};

            # Compute wrap indicator width early for correct truncation
            my $wrap_indicator_width = 0;
            if ($is_wrap_cont && $has_wrap_segment && ($entry->{indent_width} // 0) > 0) {
                $wrap_indicator_width = $entry->{indent_width};
            }

            if ($has_wrap_segment) {
                my $vis_start = $entry->{vis_start};
                my $vis_end   = $entry->{vis_end};
                my $seg_vis_len = $vis_end - $vis_start;

                # Extract just the segment portion (no indent padding)
                $expanded_content = substr($expanded_content, $vis_start, $seg_vis_len);

                $effective_scroll_col = $vis_start;
            } else {
                # Apply horizontal scroll (now in visual columns)
                if ($scroll_col > 0 && $scroll_col < length($expanded_content)) {
                    $expanded_content = substr($expanded_content, $scroll_col);
                }
                elsif ($scroll_col >= length($expanded_content)) {
                    $expanded_content = '';
                }
            }

            # Truncate to available width (accounting for wrap indicator prefix)
            my $avail_width = $width - $wrap_indicator_width;
            my $content_display_width = _display_width($expanded_content);
            if ($content_display_width > $avail_width) {
                ($expanded_content, $content_display_width) = _truncate_to_display_width($expanded_content, $avail_width);
            }

            # Compute char-level highlight range for green (new) lines in expanded hunks
            my $new_char_hl;
            if ($is_hunk_line) {
                my $hunk_idx = $entry->{hunk_idx};
                if (!exists $hunk_char_diffs{$hunk_idx}) {
                    my $hunks = $doc->vcs_hunks();
                    if ($hunks && $hunk_idx < @$hunks) {
                        my ($old_hl, $new_hl) = $class->_compute_hunk_highlights(
                            $hunks->[$hunk_idx], $doc, $doc->vcs_base_lines()
                        );
                        $hunk_char_diffs{$hunk_idx} = { old => $old_hl, new => $new_hl };
                    } else {
                        $hunk_char_diffs{$hunk_idx} = { old => {}, new => {} };
                    }
                }
                my $char_range = $hunk_char_diffs{$hunk_idx}{new}{$doc_line};
                if ($char_range) {
                    # Convert char positions to visual (tab-expanded) positions
                    my ($hl_start, $hl_end) = @$char_range;
                    my $vis_start = ($hl_start < @$char_to_visual)
                        ? $char_to_visual->[$hl_start] : length($expanded_content);
                    my $vis_end = ($hl_end < @$char_to_visual)
                        ? $char_to_visual->[$hl_end] : length($expanded_content);
                    $new_char_hl = [$vis_start, $vis_end];
                }
            }

            # Emit wrap indicator prefix: [indent spaces] + ↪ for indented continuation rows
            if ($wrap_indicator_width > 0) {
                $output .= $line_bg . (' ' x ($wrap_indicator_width - 1));
                $output .= $theme->color('wrap_indicator_fg') . Zepto::Chars->get('wrap_indicator');
                $output .= $line_bg . $theme->color('fg');
            }

            # Render with selection, syntax, match, and cursor highlighting
            $output .= $class->_render_line_with_highlights(
                $expanded_content, $doc_line, $effective_scroll_col, $avail_width,
                $view, $theme, $cursor_line, $visual_cursor_col, $is_cursor_line, \@visual_tokens,
                $full_line_content, \@visual_matches,
                $is_hunk_line ? 'new' : undef, $new_char_hl,
                \@visual_capture_regions, $is_wrap_cont
            );

            # Fill remaining space with appropriate background
            my $fill_bg = $is_cursor_line ? $line_bg
                        : $is_hunk_line   ? $line_bg
                        :                   $theme->color('bg');
            my $fill_remaining = $avail_width - $content_display_width;
            if ($fill_remaining > 0 && $view->column_select() && $view->has_selection()) {
                # Column selection may extend past line content into fill area
                my ($col_top, $col_left, $col_bottom, $col_right) = $view->column_selection();
                if ($doc_line >= $col_top && $doc_line <= $col_bottom) {
                    my $col_sel_bg = ($col_left == $col_right)
                        ? $theme->color('column_cursor_bg')
                        : $theme->color('column_selection_bg');
                    # Convert column bounds to visual positions relative to viewport
                    my $vis_left = _char_to_visual_col($full_line_content, $col_left) - $scroll_col;
                    my $vis_right = _char_to_visual_col($full_line_content, $col_right) - $scroll_col;
                    # For zero-width cursor, show one column
                    $vis_right = $vis_left + 1 if $col_left == $col_right;

                    my $fill_start = $content_display_width;
                    my $fill_end = $fill_start + $fill_remaining;

                    # Clamp selection bounds to fill region
                    my $sel_left = $vis_left < $fill_start ? $fill_start : $vis_left;
                    my $sel_right = $vis_right > $fill_end ? $fill_end : $vis_right;

                    if ($sel_right > $sel_left && $sel_left < $fill_end) {
                        # Three segments: pre-selection, selection, post-selection
                        my $pre = $sel_left - $fill_start;
                        my $sel = $sel_right - $sel_left;
                        my $post = $fill_end - $sel_right;
                        $output .= $fill_bg . (' ' x $pre) if $pre > 0;
                        $output .= $col_sel_bg . (' ' x $sel) if $sel > 0;
                        $output .= $fill_bg . (' ' x $post) if $post > 0;
                    } else {
                        $output .= $fill_bg . (' ' x $fill_remaining);
                    }
                } else {
                    $output .= $fill_bg . (' ' x $fill_remaining);
                }
            } elsif ($fill_remaining > 0) {
                $output .= $fill_bg . (' ' x $fill_remaining);
            }
        }
        else {
            # Empty line (beyond document)
            my $empty_bg = $theme->color('empty_line_bg');
            $output .= $empty_bg . (' ' x $width);
        }

        # Render minimap column for this row
        $output .= $class->_render_minimap_column($minimap_data, $screen_row, $theme)
            if $minimap_width > 0;

        $output .= CLEAR_LINE;
        $output .= RESET;
        push @text_rows, $output;
    }

    return \@text_rows;
}

# =============================================================================
# Minimap / scrollbar column rendering
# =============================================================================

# Render one row of the minimap column.
# Returns ANSI string for: separator │ + VCS indicator + braille text density
sub _render_minimap_column {
    my ($class, $minimap_data, $screen_row, $theme) = @_;

    my $output = '';
    my $minimap_bg = $theme->color('minimap_bg');

    # Separator column (thin vertical line)
    $output .= $minimap_bg . $theme->color('minimap_separator') . Zepto::Chars->get('minimap_sep');

    # Check if this row has minimap data
    my $row_data;
    if ($minimap_data && $screen_row < $minimap_data->{total_rows}) {
        $row_data = $minimap_data->{rows}[$screen_row];
    }

    # VCS indicator column — use a small dot to match the minimap's compact scale
    if ($row_data && $row_data->{vcs}) {
        my $vcs_status = $row_data->{vcs};
        my $vcs_color = $theme->color("vcs_$vcs_status") // '';
        $output .= $minimap_bg . $vcs_color . Zepto::Chars->get('minimap_vcs');
    } else {
        $output .= $minimap_bg . ' ';
    }

    # Determine background: viewport highlight or normal minimap bg
    my $in_viewport = $minimap_data
        && $screen_row >= $minimap_data->{viewport_start}
        && $screen_row <= $minimap_data->{viewport_end};
    my $text_bg = $in_viewport
        ? $theme->color('minimap_viewport_bg')
        : $minimap_bg;

    my $text_fg = $theme->color('minimap_text_fg');

    # Braille text density
    my $text_cols = MINIMAP_WIDTH - 2;  # Subtract separator + VCS column
    if ($row_data && $row_data->{braille}) {
        $output .= $text_bg . $text_fg . $row_data->{braille};
    } else {
        # Empty row (beyond document content)
        $output .= $text_bg . (' ' x $text_cols);
    }

    return $output;
}

# =============================================================================
# File Tree Panel Rendering
# =============================================================================

sub _render_tree_panel {
    my ($class, $tree, $height, $theme, $tree_width, $ui) = @_;

    my @tree_rows;
    my $panel_w = $tree_width - 1;  # Subtract border column
    my $border_char = Zepto::Chars->get('tree_vertical') || '|';

    my $focused = $tree->focused();
    my $tree_bg = $focused ? $theme->color('tree_focused_bg') : $theme->color('tree_bg');
    my $tree_fg = $theme->color('tree_fg');
    my $border_fg = $focused
        ? $theme->color('tree_border_active_fg')
        : $theme->color('tree_border_fg');

    # Get sticky headers and filter state
    my $stickies = $tree->sticky_headers();
    my $filter_active = $tree->filter_active();
    my $flat = $tree->flat_list();
    my $scroll = $tree->scroll();
    my $cursor = $tree->cursor();
    my $current_file = $tree->current_file();

    # Scrollbar data
    my $sb = $tree->scrollbar_data();
    my $has_scrollbar = ($sb->{total} > $sb->{visible});

    my $content_width = $panel_w - ($has_scrollbar ? 1 : 0);

    # Pre-compute "is_last_child" for every node in the flat list.
    # A node at index i with depth d is the last child if no subsequent node
    # shares the same depth before one appears at a lesser depth.
    my @is_last;
    for my $i (0 .. $#$flat) {
        my $d = $flat->[$i]{depth};
        my $last = 1;
        for my $j ($i + 1 .. $#$flat) {
            if ($flat->[$j]{depth} <= $d) {
                $last = ($flat->[$j]{depth} < $d) ? 1 : 0;
                last;
            }
        }
        $is_last[$i] = $last;
    }

    # Build a guide stack that tracks which ancestor depths have more siblings.
    # guide_active[level] = 1 means there are more items at that level below.
    # We walk from the top of the flat list up to the end of the visible window
    # so the stack is correct for every visible row.
    my @guide_active;
    my $walk_end = $scroll + $height;  # upper bound of what we need
    $walk_end = $#$flat if $walk_end > $#$flat;

    # Initialize guide state by walking from start to scroll position
    for my $i (0 .. $scroll - 1) {
        last if $i > $#$flat;
        my $d = $flat->[$i]{depth};
        # Clear deeper levels when we step back to a shallower depth
        for my $l ($d .. $#guide_active) { $guide_active[$l] = 0; }
        $guide_active[$d] = $is_last[$i] ? 0 : 1;
    }

    # Track which row we're rendering
    my $row_idx = 0;

    # Render sticky headers
    for my $sticky (@$stickies) {
        last if $row_idx >= $height;
        my $screen_row = $row_idx + 1;  # tree starts at row 1

        my $output = _move_to($screen_row, 1);
        $output .= $class->_render_tree_node_content(
            $sticky, $content_width, $theme, 0, 1, $focused,
            $has_scrollbar, $row_idx, $sb, undef, []
        );
        # Border
        $output .= $border_fg . $tree_bg . $border_char;
        push @tree_rows, $output;
        $row_idx++;
    }

    # Render tree content rows
    my $sticky_count = $row_idx;  # rows consumed by stickies + filter
    my $available = $height - $sticky_count;

    for my $i (0 .. $available - 1) {
        last if $row_idx >= $height;
        my $flat_idx = $scroll + $i;
        my $screen_row = $row_idx + 1;

        my $output = _move_to($screen_row, 1);

        if ($flat_idx <= $#$flat) {
            my $node = $flat->[$flat_idx];
            my $d = $node->{depth};
            my $is_cursor = ($focused && $flat_idx == $cursor);
            my $is_current = (!$node->{is_dir} && defined $current_file
                && $node->{path} eq $current_file);
            my $node_is_last = $is_last[$flat_idx];

            # Snapshot the current guide state for this node's ancestors
            my @guides_for_node;
            for my $l (0 .. $d - 1) {
                push @guides_for_node, ($guide_active[$l] ? 1 : 0);
            }

            $output .= $class->_render_tree_node_content(
                $node, $content_width, $theme, $is_cursor, 0, $focused,
                $has_scrollbar, $row_idx, $sb, $node_is_last, \@guides_for_node,
                $filter_active, $is_current
            );

            # Update guide state after rendering this node
            for my $l ($d .. $#guide_active) { $guide_active[$l] = 0; }
            $guide_active[$d] = $node_is_last ? 0 : 1;
        } else {
            # Empty row
            $output .= $tree_bg . (' ' x $content_width);
            if ($has_scrollbar) {
                $output .= $tree_bg . ' ';
            }
        }

        # Border
        $output .= $border_fg . $tree_bg . $border_char;
        push @tree_rows, $output;
        $row_idx++;
    }

    return \@tree_rows;
}

sub _render_tree_node_content {
    my ($class, $node, $width, $theme, $is_cursor, $is_sticky, $focused,
        $has_scrollbar, $row_idx, $sb, $is_last, $guides, $filter_active,
        $is_current) = @_;

    my $output = '';

    # Choose background/foreground
    my ($bg, $fg);
    if ($is_sticky) {
        $bg = $theme->color('tree_sticky_bg');
        $fg = $theme->color('tree_sticky_fg');
    } elsif ($is_cursor) {
        $bg = $theme->color('tree_cursor_bg');
        $fg = $theme->color('tree_cursor_fg');
    } elsif ($is_current) {
        $bg = $theme->color('tree_current_bg') // ($focused ? $theme->color('tree_focused_bg') : $theme->color('tree_bg'));
        $fg = $theme->color('tree_current_fg') // $theme->color('tree_fg');
    } else {
        $bg = $focused ? $theme->color('tree_focused_bg') : $theme->color('tree_bg');
        $fg = $theme->color('tree_fg');
    }

    $output .= $bg;

    # --- Flat filter mode: skip indent/icon, render full path with match highlight ---
    # Only use flat rendering when there's an actual query producing flat results;
    # empty query with filter_active still shows the normal hierarchical tree.
    if ($filter_active && !$node->{is_dir} && $node->{depth} == 0 && $node->{_filter_match_positions}) {
        my $path = $node->{name} // '';  # In flat mode, name == full path
        my $used = 1;  # leading space
        $output .= ' ';

        # File type icon (based on filename, last path component)
        my ($filename) = $path =~ m{([^/]+)$};
        $filename //= $path;
        my $icon = Zepto::Chars->file_icon($filename) // ' ';

        # VCS coloring
        my $name_fg = $fg;
        if (!$is_cursor) {
            my $vcs = $node->{vcs_status};
            if ($vcs && $theme->color("tree_vcs_$vcs")) {
                $name_fg = $theme->color("tree_vcs_$vcs");
            }
            $name_fg = BOLD . $name_fg if $is_current;
        }

        # Render icon
        $output .= $name_fg . $bg . "$icon ";
        $used += 2;  # icon + space

        my $name_space = $width - $used;

        # Truncate from the LEFT so filename stays visible: …eep/path/file.pm
        my $display_path = $path;
        my $trim_offset = 0;  # how many chars trimmed from the left
        if ($name_space > 0 && length($path) > $name_space) {
            $trim_offset = length($path) - ($name_space - 1);  # 1 for ellipsis
            $display_path = "\x{2026}" . substr($path, $trim_offset);
        } elsif ($name_space <= 0) {
            $display_path = '';
        }

        # Find where filename starts in display string (for dim dirs / bright filename)
        my $filename_start_in_path = length($path) - length($filename);
        my $dir_fg = $is_cursor ? $fg : $theme->color('tree_result_dir_fg');
        my $file_fg = $name_fg;

        # Build match highlight set (adjusted for left-truncation)
        my $match_positions = $node->{_filter_match_positions};
        my %highlight_cols;
        if ($match_positions && @$match_positions) {
            for my $pos (@$match_positions) {
                my $display_col;
                if ($trim_offset > 0) {
                    # Skip positions that were trimmed; offset remaining by trim + 1 for ellipsis
                    next if $pos < $trim_offset;
                    $display_col = $pos - $trim_offset + 1;
                } else {
                    $display_col = $pos;
                }
                $highlight_cols{$display_col} = 1 if $display_col >= 0 && $display_col < length($display_path);
            }
        }

        # Render each character with: match highlight, dim dirs, bright filename
        my $match_fg = $theme->color('tree_match_fg');
        for my $ci (0 .. length($display_path) - 1) {
            my $ch = substr($display_path, $ci, 1);
            # Map display column back to path position to decide dir vs filename
            my $path_pos;
            if ($trim_offset > 0 && $ci == 0) {
                $path_pos = -1;  # ellipsis char — treat as dir part
            } elsif ($trim_offset > 0) {
                $path_pos = $trim_offset + $ci - 1;
            } else {
                $path_pos = $ci;
            }

            my $base_fg = ($path_pos >= $filename_start_in_path) ? $file_fg : $dir_fg;
            if ($highlight_cols{$ci}) {
                $output .= $match_fg . $bg . $ch;
            } else {
                $output .= $base_fg . $bg . $ch;
            }
        }

        # Pad remainder
        my $pad = $width - $used - length($display_path);
        $output .= $bg . (' ' x $pad) if $pad > 0;

        # Reset bold/attributes before scrollbar and border
        $output .= RESET if $is_current;

        # Scrollbar column
        if ($has_scrollbar) {
            my $sb_bg = $theme->color('tree_scrollbar_bg');
            if ($row_idx >= $sb->{thumb_start} && $row_idx < $sb->{thumb_end}) {
                $output .= $theme->color('tree_scrollbar_fg') . $sb_bg . "\x{2588}";
            } else {
                $output .= $sb_bg . ' ';
            }
        }

        return $output;
    }

    my $depth = $node->{depth} // 0;
    my $indent_fg = $theme->color('tree_indent_fg');

    # Get tree drawing characters
    my $ch_vertical = Zepto::Chars->get('tree_vertical');   # │
    my $ch_branch   = Zepto::Chars->get('tree_branch');     # ├
    my $ch_last     = Zepto::Chars->get('tree_last');       # ╰
    my $ch_dash     = Zepto::Chars->get('tree_dash');       # ─
    my $ch_arrow_r  = Zepto::Chars->get('tree_arrow_right'); # ▸
    my $ch_arrow_d  = Zepto::Chars->get('tree_arrow_down');  # ▾

    # === Left padding (1 space) ===
    $output .= ' ';
    my $used = 1;

    if ($depth == 0) {
        # Depth 0: arrow + space (dirs) or 2 spaces (files)
        if ($node->{is_dir}) {
            my $arrow_fg = $is_cursor ? $fg : $theme->color('tree_dir_fg');
            my $arrow = $node->{expanded} ? $ch_arrow_d : $ch_arrow_r;
            $output .= $arrow_fg . $bg . $arrow . ' ';
        } else {
            $output .= $bg . '  ';
        }
        $used += 2;
    } elsif ($is_sticky) {
        # Sticky headers: indented to match original depth (spaces, no guide lines)
        my $indent_chars = 2 * $depth + 1;  # spaces before arrow/dash
        $output .= $bg . (' ' x $indent_chars);
        $used += $indent_chars;
        # Arrow for dirs
        if ($node->{is_dir}) {
            my $arrow_fg = $is_cursor ? $fg : $theme->color('tree_sticky_fg');
            my $arrow = $node->{expanded} ? $ch_arrow_d : $ch_arrow_r;
            $output .= $arrow_fg . $bg . $arrow;
        } else {
            $output .= $ch_dash;
        }
        $used += 1;
    } else {
        # Depth > 0: indent zone with guides aligned under parent folder icons,
        # then connector, then dash (files) or arrow (dirs).
        #
        # Guide char for ancestor level k sits at column 4+2*k, which is the
        # icon column of the depth-k directory ancestor.  The connector char
        # (├ or ╰) sits at column 2+2*depth (= icon column of the parent dir).
        $output .= $indent_fg . $bg;

        my $connector_col = 2 + 2 * $depth;
        for my $col (2 .. $connector_col - 1) {
            if ($col >= 4 && ($col - 4) % 2 == 0) {
                my $guide_level = ($col - 4) / 2;
                if ($guides && $guide_level < scalar @$guides && $guides->[$guide_level]) {
                    $output .= $ch_vertical;
                } else {
                    $output .= ' ';
                }
            } else {
                $output .= ' ';
            }
        }
        $used += $connector_col - 2;

        if ($node->{is_dir}) {
            # Dirs: arrow replaces connector for a cleaner look
            my $arrow_fg = $is_cursor ? $fg : $theme->color('tree_dir_fg');
            my $arrow = $node->{expanded} ? $ch_arrow_d : $ch_arrow_r;
            $output .= $arrow_fg . $bg . $arrow . ' ';
        } else {
            # Files: connector (├ or ╰) + dash
            if ($is_last) {
                $output .= $ch_last;
            } else {
                $output .= $ch_branch;
            }
            $output .= $ch_dash;
        }
        $used += 2;
    }

    # === Icon ===
    my $icon;
    if ($node->{is_dir}) {
        $icon = $node->{expanded}
            ? Zepto::Chars->get('folder_open')
            : Zepto::Chars->get('folder');
    } else {
        $icon = Zepto::Chars->file_icon($node->{name});
    }
    $icon //= ' ';

    # Name color: VCS status overrides default
    my $name_fg;
    if (!$is_cursor && !$is_sticky) {
        my $vcs = $node->{vcs_status};
        if ($vcs && $theme->color("tree_vcs_$vcs")) {
            $name_fg = $theme->color("tree_vcs_$vcs");
        } elsif ($node->{is_dir}) {
            $name_fg = $theme->color('tree_dir_fg');
        } else {
            $name_fg = $fg;
        }
        # Bold for current file (active tab) regardless of VCS color
        $name_fg = BOLD . $name_fg if $is_current;
    } else {
        $name_fg = $fg;
    }

    my $icon_str = "$icon ";
    $used += 2;  # icon + space

    # === Name (truncated if needed) ===
    my $name = $node->{name} // '';
    my $name_space = $width - $used;

    if ($name_space > 0) {
        if (length($name) > $name_space) {
            $name = substr($name, 0, $name_space - 1) . "\x{2026}";  # …
        }
    } else {
        $name = '';
    }

    # Render icon
    if ($node->{is_dir}) {
        $output .= $theme->color('tree_dir_fg') . $bg . $icon_str;
    } else {
        $output .= $name_fg . $bg . $icon_str;
    }

    # Render name with potential filter match highlighting
    my $match_positions = $node->{_filter_match_positions};
    if ($match_positions && @$match_positions) {
        my $path = $node->{path} // '';
        my $name_start = length($path) - length($node->{name} // '');
        my %highlight_cols;
        for my $pos (@$match_positions) {
            my $rel = $pos - $name_start;
            $highlight_cols{$rel} = 1 if $rel >= 0 && $rel < length($name);
        }

        my $match_fg = $theme->color('tree_match_fg');
        for my $ci (0 .. length($name) - 1) {
            if ($highlight_cols{$ci}) {
                $output .= $match_fg . $bg . substr($name, $ci, 1);
            } else {
                $output .= $name_fg . $bg . substr($name, $ci, 1);
            }
        }
    } else {
        $output .= $name_fg . $bg . $name;
    }

    # Pad remainder
    my $total_used = $used + length($name);
    my $pad = $width - $total_used;
    $output .= $bg . (' ' x $pad) if $pad > 0;

    # Reset bold/attributes before scrollbar and border
    $output .= RESET if $is_current;

    # Scrollbar column
    if ($has_scrollbar) {
        my $sb_bg = $theme->color('tree_scrollbar_bg');
        if ($row_idx >= $sb->{thumb_start} && $row_idx <= $sb->{thumb_end}) {
            $output .= $theme->color('tree_scrollbar_fg') . $sb_bg . "\x{2588}";  # █
        } else {
            $output .= $sb_bg . ' ';
        }
    }

    return $output;
}

# =============================================================================
# Character-level diff for inline hunk highlighting
# =============================================================================

# Compute changed character ranges between two lines via common prefix/suffix.
# Returns { old_range => [start, end], new_range => [start, end] }
# where [start, end) marks the changed region in each string.
sub _char_diff_ranges {
    my ($old, $new) = @_;

    my $old_len = length($old);
    my $new_len = length($new);
    my $min_len = $old_len < $new_len ? $old_len : $new_len;

    # Common prefix
    my $prefix = 0;
    while ($prefix < $min_len && substr($old, $prefix, 1) eq substr($new, $prefix, 1)) {
        $prefix++;
    }

    # Common suffix (not overlapping prefix)
    my $suffix = 0;
    while ($suffix < ($min_len - $prefix) &&
           substr($old, $old_len - 1 - $suffix, 1) eq substr($new, $new_len - 1 - $suffix, 1)) {
        $suffix++;
    }

    return {
        old_range => [$prefix, $old_len - $suffix],
        new_range => [$prefix, $new_len - $suffix],
    };
}

# Compute char-level diff highlights for all line pairs in a hunk.
# Returns { old => { base_line_idx => [start, end] }, new => { doc_line => [start, end] } }
sub _compute_hunk_highlights {
    my ($class, $hunk, $doc, $base_lines) = @_;

    my %old_hl;
    my %new_hl;

    return (\%old_hl, \%new_hl) unless $hunk->{type} eq 'modified';

    my $bl = $hunk->{base_lines};
    my $cl = $hunk->{current_lines};
    my $pairs = @$bl < @$cl ? scalar @$bl : scalar @$cl;

    for my $i (0 .. $pairs - 1) {
        my $old_text = ($base_lines && $bl->[$i] < @$base_lines)
            ? $base_lines->[$bl->[$i]] : '';
        my $new_text = $cl->[$i] < $doc->line_count()
            ? $doc->get_line_content($cl->[$i]) : '';

        my $diff = _char_diff_ranges($old_text, $new_text);

        # Only store if there's an actual change region (not identical lines)
        if ($diff->{old_range}[0] < $diff->{old_range}[1] ||
            $diff->{new_range}[0] < $diff->{new_range}[1]) {
            $old_hl{$bl->[$i]} = $diff->{old_range};
            $new_hl{$cl->[$i]} = $diff->{new_range};
        }
    }

    # Unpaired extra lines: highlight entire line
    for my $i ($pairs .. $#$bl) {
        $old_hl{$bl->[$i]} = [0, length($base_lines->[$bl->[$i]] // '')];
    }
    for my $i ($pairs .. $#$cl) {
        my $content = $cl->[$i] < $doc->line_count() ? $doc->get_line_content($cl->[$i]) : '';
        $new_hl{$cl->[$i]} = [0, length($content)];
    }

    return (\%old_hl, \%new_hl);
}

# Render an "old" (base) line from an expanded diff hunk
# These lines show deleted/modified-from content with red background, no line number
sub _render_old_line_row {
    my ($class, $doc, $view, $theme, $width, $gutter_width, $entry, $highlighter, $base_hl_ref, $char_highlights) = @_;

    my $output = '';
    my $base_line_idx = $entry->{base_line};

    # Gutter: use yellow (vcs_modified) for modified hunks, red for deleted hunks
    my $gutter_bg = $theme->color('diff_old_gutter_bg');
    my $hunks = $doc->vcs_hunks();
    my $h = $hunks->[$entry->{hunk_idx}];
    my $vcs_color = ($h && $h->{type} eq 'modified')
        ? $theme->color('vcs_modified')
        : $theme->color('vcs_deleted');
    if ($entry->{wrap_index} && $entry->{wrap_index} > 0) {
        # Wrap continuation: extend diff gutter background but no VCS indicator
        $output .= $gutter_bg . $vcs_color . Zepto::Chars->get('vcs_expanded');
        $output .= $gutter_bg . ' ' x ($gutter_width - 1);
    } else {
        my $vcs_char = Zepto::Chars->get('vcs_expanded');  # Fat block for expanded lines
        $output .= $gutter_bg . $vcs_color . $vcs_char;
        # Blank padding for the rest of the gutter
        $output .= $gutter_bg . ' ' x ($gutter_width - 1);
    }

    # Line content from base
    my $line_bg = $theme->color('diff_old_bg');
    my $fg = $theme->color('fg');
    $output .= $line_bg . $fg;

    my $base_lines = $doc->vcs_base_lines();
    my $line_content = '';
    if ($base_lines && $base_line_idx < scalar @$base_lines) {
        $line_content = $base_lines->[$base_line_idx];
    }

    # Syntax highlight using a base highlighter (lazily created)
    my $tokens = [];
    if ($highlighter && $line_content ne '') {
        if (!$$base_hl_ref) {
            # Create a base highlighter with the same grammar (use ref to avoid require)
            $$base_hl_ref = ref($highlighter)->new();
            my $filename = $doc->filename() // '';
            $$base_hl_ref->set_file($filename) if $filename;

            # Pre-tokenize all base lines up to the one we need so state is correct
            if ($$base_hl_ref && $base_lines) {
                for my $i (0 .. $base_line_idx) {
                    my $bl = $base_lines->[$i] // '';
                    $$base_hl_ref->tokenize_line($bl, $i);
                }
            }
        } else {
            # Ensure all preceding lines have been tokenized for correct state
            # The highlighter caches states, so already-tokenized lines are fast
            if ($base_lines) {
                for my $i (0 .. $base_line_idx) {
                    my $bl = $base_lines->[$i] // '';
                    $$base_hl_ref->tokenize_line($bl, $i);
                }
            }
        }
        ($tokens) = $$base_hl_ref->tokenize_line($line_content, $base_line_idx);
    }

    # Expand tabs
    my ($expanded_content, $char_to_visual) = _expand_tabs($line_content);

    # Convert token positions to visual positions
    my @visual_tokens;
    for my $tok (@$tokens) {
        my $vis_start = $char_to_visual->[$tok->{start}] // 0;
        my $vis_end = $tok->{end} < @$char_to_visual
            ? $char_to_visual->[$tok->{end}]
            : length($expanded_content);
        push @visual_tokens, {
            start => $vis_start,
            end => $vis_end,
            type => $tok->{type},
        };
    }

    # Apply horizontal scroll or wrap segment slicing
    my $scroll_col;
    my $segment_end;
    if (defined $entry->{vis_start}) {
        # Word-wrapped old line: slice to the segment's visual range
        $scroll_col = $entry->{vis_start};
        $segment_end = $entry->{vis_end};
    } else {
        $scroll_col = $view->scroll_col();
    }
    if ($scroll_col > 0 && $scroll_col < length($expanded_content)) {
        $expanded_content = substr($expanded_content, $scroll_col);
    } elsif ($scroll_col >= length($expanded_content)) {
        $expanded_content = '';
    }

    # Truncate to segment end or viewport width
    my $display_limit = defined $segment_end ? ($segment_end - $scroll_col) : $width;
    # For wrap continuations, add indent prefix
    my $indent_prefix = '';
    if (defined $entry->{wrap_index} && $entry->{wrap_index} > 0) {
        my $indent_width = $entry->{indent_width} // 0;
        my $wrap_char = Zepto::Chars->get('wrap_indicator');
        if ($indent_width > 1) {
            $indent_prefix = (' ' x ($indent_width - 1)) . $wrap_char;
        } elsif ($indent_width > 0) {
            $indent_prefix = $wrap_char;
        } else {
            $indent_prefix = $wrap_char;
        }
        $display_limit -= length($indent_prefix);
        $display_limit = 0 if $display_limit < 0;
    }

    my $old_content_display_width = _display_width($expanded_content);
    if ($old_content_display_width > $display_limit) {
        ($expanded_content, $old_content_display_width) = _truncate_to_display_width($expanded_content, $display_limit);
    }

    # Prepend indent prefix for wrap continuations
    if (length($indent_prefix) > 0) {
        $expanded_content = $indent_prefix . $expanded_content;
        $old_content_display_width += length($indent_prefix);
    }

    # Render character by character with syntax highlighting on red background
    my $len = length($expanded_content);

    # Build syntax color lookup (adjusted for scroll)
    my @syntax_fg;
    for my $tok (@visual_tokens) {
        my $color = $theme->color("syntax_$tok->{type}");
        next unless $color;
        my $start = $tok->{start} - $scroll_col;
        my $end = $tok->{end} - $scroll_col;
        $start = 0 if $start < 0;
        next if $start >= $len;
        $end = $len if $end > $len;
        next if $end <= 0;
        for my $c ($start .. $end - 1) {
            $syntax_fg[$c] = $color if $c >= 0 && $c < $len;
        }
    }

    # Convert char highlight range to visual positions for stronger-red background
    my $hl_bg = $theme->color('diff_old_highlight_bg');
    my ($vis_hl_start, $vis_hl_end) = (-1, -1);
    if ($char_highlights && $char_to_visual) {
        my ($hl_start, $hl_end) = @$char_highlights;
        $vis_hl_start = ($hl_start < @$char_to_visual)
            ? $char_to_visual->[$hl_start] : length($expanded_content);
        $vis_hl_end = ($hl_end < @$char_to_visual)
            ? $char_to_visual->[$hl_end] : length($expanded_content);
        # Adjust for horizontal scroll
        $vis_hl_start -= $scroll_col;
        $vis_hl_end -= $scroll_col;
    }

    my $last_bg = '';
    my $last_fg = '';
    for my $i (0 .. $len - 1) {
        my $char = substr($expanded_content, $i, 1);
        next if ord($char) < 0x20;  # Strip control chars — never pass file content to terminal unescaped
        my $char_fg = $syntax_fg[$i] // $fg;
        my $bg = ($i >= $vis_hl_start && $i < $vis_hl_end) ? $hl_bg : $line_bg;
        if ($bg ne $last_bg || $char_fg ne $last_fg) {
            $output .= ATTR_RESET . $bg . $char_fg;
            $last_bg = $bg;
            $last_fg = $char_fg;
        }
        $output .= $char;
    }

    # Fill rest with red background (use display width for correct padding)
    my $fill_cols = $width - $old_content_display_width;
    $output .= $line_bg . (' ' x $fill_cols) if $fill_cols > 0;

    return $output;
}

# Render a line with selection, syntax, match, and crosshair highlighting
# $content: tab-expanded content for this line
# $orig_content: original content (with tabs) for position conversion
# $cursor_col: visual cursor column (already converted)
# $matches: array of {start, end, is_current} for find matches on this line
sub _render_line_with_highlights {
    my ($class, $content, $line_num, $scroll_col, $width, $view, $theme, $cursor_line, $cursor_col, $is_cursor_line, $tokens, $orig_content, $matches, $diff_mode, $char_highlight, $capture_regions, $is_wrap_cont) = @_;

    my $output = '';
    my $len = length($content);

    # Background colors — use diff background when in expanded hunk
    my $bg = ($diff_mode && $diff_mode eq 'new')
        ? $theme->color('diff_new_bg')
        : $theme->color('bg');

    # Char-level highlight range for stronger green background on changed chars
    my $diff_hl_bg;
    my ($vis_hl_start, $vis_hl_end) = (-1, -1);
    if ($char_highlight && $diff_mode && $diff_mode eq 'new') {
        $diff_hl_bg = $theme->color('diff_new_highlight_bg');
        $vis_hl_start = $char_highlight->[0] - $scroll_col;
        $vis_hl_end = $char_highlight->[1] - $scroll_col;
    }
    my $line_bg = ($diff_mode && $diff_mode eq 'new')
        ? $theme->color('diff_new_cursor_bg')
        : $theme->color('cursor_line_bg');
    my $fg = $theme->color('fg');
    my $match_bg = $theme->color('match_bg');
    my $match_fg = $theme->color('match_fg');
    my $current_match_bg = $theme->color('current_match_bg');
    my $current_match_fg = $theme->color('current_match_fg');

    # Build capture region lookup (maps visible column → {group, is_current})
    my @capture_group;       # column → group number
    my @capture_is_current;  # column → is this the current match?
    if ($capture_regions && @$capture_regions) {
        for my $cr (@$capture_regions) {
            my $start = $cr->{start} - $scroll_col;
            my $end = $cr->{end} - $scroll_col;
            $start = 0 if $start < 0;
            next if $start >= $len;
            $end = $len if $end > $len;
            next if $end <= 0;
            for my $c ($start .. $end - 1) {
                if ($c >= 0 && $c < $len) {
                    $capture_group[$c] = $cr->{group};
                    $capture_is_current[$c] = $cr->{is_current};
                }
            }
        }
    }

    # Build match highlight lookup (adjusted for scroll)
    # Maps visible column → 'current' or 'other' or undef
    my @match_type;
    if ($matches && @$matches) {
        for my $m (@$matches) {
            # Adjust match positions for scroll
            my $start = $m->{start} - $scroll_col;
            my $end = $m->{end} - $scroll_col;

            # Clamp to visible range
            $start = 0 if $start < 0;
            next if $start >= $len;
            $end = $len if $end > $len;
            next if $end <= 0;

            for my $c ($start .. $end - 1) {
                if ($c >= 0 && $c < $len) {
                    # Current match takes priority over other matches
                    if ($m->{is_current} || !$match_type[$c]) {
                        $match_type[$c] = $m->{is_current} ? 'current' : 'other';
                    }
                }
            }
        }
    }

    # Build syntax color lookup from tokens (adjusted for scroll)
    # Maps visible column → syntax foreground color
    my @syntax_fg;
    if ($tokens && @$tokens) {
        for my $tok (@$tokens) {
            my $type = $tok->{type};
            my $color = $theme->color("syntax_$type");
            next unless $color;  # Skip if no color defined for this type

            # Adjust token positions for scroll
            my $start = $tok->{start} - $scroll_col;
            my $end = $tok->{end} - $scroll_col;

            # Clamp to visible range
            $start = 0 if $start < 0;
            next if $start >= $len;  # Token entirely scrolled off right
            $end = $len if $end > $len;
            next if $end <= 0;  # Token entirely scrolled off left

            for my $c ($start .. $end - 1) {
                $syntax_fg[$c] = $color if $c >= 0 && $c < $len;
            }
        }
    }

    # Get selection info
    my $has_selection = $view->has_selection();
    my $is_column_select = $view->column_select();
    my ($sel_start, $sel_end) = (-1, -1);
    my $sel_bg_color = $theme->color('selection_bg');

    if ($has_selection && $is_column_select) {
        # Column (rectangular) selection: fixed column range on each line
        # Skip continuation lines — column selection only applies to first row
        my ($col_top, $col_left, $col_bottom, $col_right) = $view->column_selection();
        $sel_bg_color = $theme->color('column_selection_bg');

        if (!$is_wrap_cont && $line_num >= $col_top && $line_num <= $col_bottom) {
            my $visual_left = _char_to_visual_col($orig_content, $col_left);
            my $visual_right = _char_to_visual_col($orig_content, $col_right);
            $sel_start = $visual_left - $scroll_col;
            $sel_end = $visual_right - $scroll_col;
            $sel_start = 0 if $sel_start < 0;
            $sel_end = 0 if $sel_end < 0;

            # Zero-width column cursor: highlight single column position
            if ($col_left == $col_right && $sel_start >= 0) {
                $sel_bg_color = $theme->color('column_cursor_bg');
                $sel_end = $sel_start + 1;  # One column wide for cursor bar
            }
        }
    }
    elsif ($has_selection) {
        # Linear selection
        my ($sel_start_line, $sel_start_col, $sel_end_line, $sel_end_col) = $view->selection();
        my $line_in_selection = ($line_num >= $sel_start_line && $line_num <= $sel_end_line);

        if ($line_in_selection) {
            $sel_start = 0;
            $sel_end = $len;

            if ($line_num == $sel_start_line) {
                my $visual_sel_start = _char_to_visual_col($orig_content, $sel_start_col);
                $sel_start = $visual_sel_start - $scroll_col;
                $sel_start = 0 if $sel_start < 0;
            }

            if ($line_num == $sel_end_line) {
                my $visual_sel_end = _char_to_visual_col($orig_content, $sel_end_col);
                $sel_end = $visual_sel_end - $scroll_col;
                $sel_end = 0 if $sel_end < 0;
            }
        }
    }

    # Render character by character with appropriate backgrounds and foregrounds
    # Priority: current_match > other_match > selection > cursor_line/col > syntax > default
    my $last_style = '';
    for (my $i = 0; $i < $len; $i++) {
        my $char = substr($content, $i, 1);
        next if ord($char) < 0x20;  # Strip control chars — never pass file content to terminal unescaped
        my ($char_bg, $char_fg, $style_key);

        # Check if in a find match (highest priority for visibility)
        if ($match_type[$i]) {
            if ($match_type[$i] eq 'current') {
                # Check for capture group sub-region
                if ($capture_group[$i]) {
                    my $grp = $capture_group[$i];
                    my $color_idx = (($grp - 1) % 4) + 1;
                    $char_bg = $theme->color("capture_group_${color_idx}_bg");
                    $char_fg = $current_match_fg;
                    $style_key = "curmatch_g$grp";
                } else {
                    $char_bg = $current_match_bg;
                    $char_fg = $current_match_fg;
                    $style_key = "curmatch";
                }
            } else {
                # Non-current match: check for capture group sub-region (dim tint)
                if ($capture_group[$i]) {
                    my $grp = $capture_group[$i];
                    my $color_idx = (($grp - 1) % 4) + 1;
                    $char_bg = $theme->color("capture_group_${color_idx}_dim_bg");
                    $char_fg = $match_fg;
                    $style_key = "match_g$grp";
                } else {
                    $char_bg = $match_bg;
                    $char_fg = $match_fg;
                    $style_key = "match";
                }
            }
        }
        # Check if in selection (linear or column)
        elsif ($sel_start >= 0 && $i >= $sel_start && $i < $sel_end) {
            $char_bg = $sel_bg_color;
            $char_fg = $syntax_fg[$i] // $fg;  # Preserve syntax highlighting
            my $sel_prefix = $is_column_select ? "csel:" : "sel:";
            $style_key = $sel_prefix . ($syntax_fg[$i] // 'def');
        }
        # Check crosshair highlighting
        elsif ($is_cursor_line) {
            $char_bg = $line_bg;
            $char_fg = $syntax_fg[$i] // $fg;
            $style_key = "line:" . ($syntax_fg[$i] // 'def');
        }
        # Check char-level diff highlight (stronger green for changed chars)
        elsif ($diff_hl_bg && $i >= $vis_hl_start && $i < $vis_hl_end) {
            $char_bg = $diff_hl_bg;
            $char_fg = $syntax_fg[$i] // $fg;
            $style_key = "diffhl:" . ($syntax_fg[$i] // 'def');
        }
        else {
            $char_bg = $bg;
            $char_fg = $syntax_fg[$i] // $fg;
            $style_key = "bg:" . ($syntax_fg[$i] // 'def');
        }

        # Only emit escape codes when style changes
        # ATTR_RESET clears bold/italic so syntax_bold/italic/heading work correctly
        if ($style_key ne $last_style) {
            $output .= ATTR_RESET . $char_bg . $char_fg;
            $last_style = $style_key;
        }

        $output .= $char;
    }

    return $output;
}

# Render the status bar with Nerd Font segments
sub _render_status_bar {
    my ($class, $doc, $view, $theme, $cols, $message, $status_hint, $hint_color) = @_;

    my $output = '';
    my $ar = Zepto::Chars->get('arrow_right');

    # If there's a message, show it simply
    if ($message) {
        $output .= $theme->color('status_bg') . $theme->color('warning_fg');
        $output .= ' ' . $message;
        my $padding = $cols - length($message) - 1;
        $output .= ' ' x $padding if $padding > 0;
        $output .= CLEAR_LINE . RESET;
        return $output;
    }

    # Get file info — show relative path (tab bar shows filename, status bar shows path)
    my $display_path = $doc ? ($doc->path() // $doc->filename()) : '[No file]';
    my $is_dirty = $doc && $doc->is_dirty();
    my $modified_icon = $is_dirty ? ' ' . Zepto::Chars->get('modified') : '';

    # Build left segment: path with optional modified indicator
    my $file_text = " $display_path$modified_icon ";
    my $file_width = length($display_path) + 2;
    $file_width += 2 if $is_dirty;  # For modified icon + space

    # Build right segment: contextual hint (dimmed)
    my $hint_text = '';
    my $hint_width = 0;
    if ($status_hint) {
        $hint_text = "$status_hint ";
        $hint_width = length($hint_text);
    }

    # Calculate segment overhead (arrow char only in nerd font mode)
    my $segment_overhead = Zepto::Chars->enabled() ? 1 : 0;

    # Render: [file segment][arrow][col indicator?][arrow][middle fill][hint]
    # File segment
    $output .= $theme->color('status_file_bg') . $theme->color('status_file_fg');
    $output .= " $display_path";
    if ($is_dirty) {
        $output .= $theme->color('status_modified_fg');
        $output .= " " . Zepto::Chars->get('modified');
        $output .= $theme->color('status_file_fg');
    }
    $output .= ' ';

    # Column selection indicator segment
    my $col_text = '';
    my $col_width = 0;
    if ($view && $view->column_select()) {
        if ($view->has_selection()) {
            my ($top, $left, $bottom, $right) = $view->column_selection();
            my $lines = $bottom - $top + 1;
            my $rect_cols = $right - $left;
            if ($rect_cols > 0) {
                $col_text = " COL ${lines}\x{00D7}${rect_cols} ";  # e.g. "COL 5×3"
            } else {
                $col_text = " COL ${lines} lines ";
            }
        } else {
            $col_text = " COL MODE ";
        }
        $col_width = length($col_text);
        $col_width += $segment_overhead;  # Arrow char
    }

    # Arrow transition: file -> column indicator or middle
    if (Zepto::Chars->enabled()) {
        if ($col_width > 0) {
            # file -> column indicator
            $output .= $theme->color('column_indicator_bg') . $theme->color('status_file_edge');
            $output .= $ar;
            # Column indicator text
            $output .= $theme->color('column_indicator_fg') . $col_text;
            # column indicator -> middle
            $output .= $theme->color('status_bg') . $theme->color('column_indicator_edge');
            $output .= $ar;
        } else {
            # file -> middle
            $output .= $theme->color('status_bg') . $theme->color('status_file_edge');
            $output .= $ar;
        }
    } elsif ($col_width > 0) {
        # No nerd font, just show text
        $output .= $theme->color('column_indicator_bg') . $theme->color('column_indicator_fg');
        $output .= $col_text;
    }

    # Middle fill (account for column indicator width)
    my $middle = $cols - $file_width - $segment_overhead - $col_width - $hint_width;
    $middle = 0 if $middle < 0;
    $output .= $theme->color('status_bg') . $theme->color('status_fg');
    $output .= ' ' x $middle if $middle > 0;

    # Hint (right-aligned, colored by hunk type)
    if ($hint_width > 0) {
        $output .= $theme->color('status_bg');
        $output .= $hint_color // $theme->color('gutter_fg');
        $output .= $hint_text;
    }

    $output .= CLEAR_LINE;
    $output .= RESET;

    return $output;
}

# Store and retrieve status button positions for click handling
{
    my $_status_buttons = [];
sub _set_status_buttons { shift; $_status_buttons = shift; }
sub get_status_buttons { return @{$_status_buttons}; }
}

# Store and retrieve ruler button positions for click handling
{
    my $_ruler_buttons = [];
    sub _set_ruler_buttons { shift; $_ruler_buttons = shift; }
    sub get_ruler_buttons { return @{$_ruler_buttons}; }
}

# Store and retrieve palette button positions and geometry for click handling
{
    my $_palette_buttons = [];
    my $_palette_geometry = {};
    sub _set_palette_buttons { shift; $_palette_buttons = shift; }
    sub get_palette_buttons { return @{$_palette_buttons}; }
    sub _set_palette_geometry { shift; $_palette_geometry = shift; }
    sub get_palette_geometry { return $_palette_geometry; }
}

# =============================================================================
# Context-Aware Status Bar with Pills
# =============================================================================

# Render a single pill and return (output_string, display_width)
sub _render_pill {
    my ($class, $theme, $icon, $label, $shortcut, $fg_key, $bg_key, $edge_key, $prev_bg_key) = @_;

    my $output = '';
    my $rl = Zepto::Chars->get('round_left');
    my $rr = Zepto::Chars->get('round_right');
    my $nerd_font = Zepto::Chars->enabled();

    my $text = '';
    $text .= "$icon " if $icon;
    $text .= $label if $label;
    $text .= " $shortcut" if $shortcut;

    my $width;

    if ($nerd_font) {
        # Nerd font pill: edge_bg + round_left(fg=pill_bg) + pill_content + round_right(fg=pill_bg) + edge_bg
        $output .= $theme->color($bg_key) . $theme->color($fg_key);
        $output .= " $text ";
        $width = length($text) + 2;  # spaces
    } else {
        $output .= $theme->color($bg_key) . $theme->color($fg_key);
        $output .= " $text ";
        $width = length($text) + 2;
    }

    return ($output, $width);
}

sub _render_context_status_bar {
    my ($class, $doc, $view, $theme, $cols, $message, $message_is_error, $ui, $word_wrap_active) = @_;

    my $output = '';
    my @buttons;
    my $ar = Zepto::Chars->get('arrow_right');
    my $nerd_font = Zepto::Chars->enabled();

    # If there's a message, show it simply
    if ($message) {
        my $fg = $message_is_error ? $theme->color('error_fg') : $theme->color('warning_fg');
        $output .= $theme->color('status_bg') . $fg;
        $output .= ' ' . $message;
        my $padding = $cols - length($message) - 1;
        $output .= ' ' x $padding if $padding > 0;
        $output .= CLEAR_LINE . RESET;
        $class->_set_status_buttons([]);
        return $output;
    }

    # Tree-focused: show simplified hint bar
    my $tree = $ui->{file_tree};
    if ($tree && $tree->focused()) {
        my $cursor_icon = Zepto::Chars->get('cursor_pos');
        my $node = $tree->cursor_node();
        my $node_path = $node ? $node->{path} : '';

        $output .= $theme->color('status_file_bg') . $theme->color('status_file_fg');
        my $left_text = " $cursor_icon $node_path ";
        $output .= $left_text;
        my $left_width = length($left_text);

        if ($nerd_font) {
            my $tree_round_r = Zepto::Chars->get('round_right');
            $output .= $theme->color('status_bg') . $theme->color('status_file_edge');
            $output .= $tree_round_r;
            $left_width += 1;
        }

        my $round_l = Zepto::Chars->get('round_left');
        my $round_r = Zepto::Chars->get('round_right');

        # Right: Open File + palette trigger pills
        my $open_icon = Zepto::Chars->get('folder_open');
        my $open_text = " $open_icon Open \x{2303}O ";
        my $open_width = length($open_text) + ($nerd_font ? 2 : 0);

        my $palette_icon = Zepto::Chars->get('palette');
        my $palette_text = " $palette_icon Commands \x{2303}\x{2423} ";  # ⌃␣
        my $palette_width = length($palette_text) + ($nerd_font ? 2 : 0);

        my $right_width = $open_width + 1 + $palette_width;  # +1 for gap

        # Middle: tree-context hint pills
        my $nav_icon = Zepto::Chars->get('cursor_pos');
        my @tree_pills = (
            { text => "$nav_icon \x{2191}\x{2193}", fg => 'pill_action_fg', bg => 'pill_action_bg', edge => 'pill_action_edge' },
            { text => "\x{2190}\x{2192} fold",      fg => 'pill_action_fg', bg => 'pill_action_bg', edge => 'pill_action_edge' },
            { text => "\x{21B5} open",               fg => 'pill_action_fg', bg => 'pill_action_bg', edge => 'pill_action_edge' },
            { text => "Esc back",                    fg => 'pill_action_fg', bg => 'pill_action_bg', edge => 'pill_action_edge' },
        );

        my $available = $cols - $left_width - $right_width;
        $available = 0 if $available < 0;
        my $center_col = $left_width + 1;

        for my $pill (@tree_pills) {
            my $pw = length($pill->{text}) + 2 + ($nerd_font ? 3 : 1);
            last if ($center_col - $left_width) + $pw > $available;

            if ($nerd_font) {
                $output .= $theme->color('status_bg') . $theme->color($pill->{edge});
                $output .= $round_l;
                $center_col += 1;
            }
            $output .= $theme->color($pill->{bg}) . $theme->color($pill->{fg});
            $output .= " $pill->{text} ";
            $center_col += length($pill->{text}) + 2;
            if ($nerd_font) {
                $output .= $theme->color('status_bg') . $theme->color($pill->{edge});
                $output .= $round_r;
                $center_col += 1;
            }
            $output .= $theme->color('status_bg') . ' ';
            $center_col += 1;
        }

        # Fill remaining space
        my $remaining = $cols - $center_col - $right_width + 1;
        $remaining = 0 if $remaining < 0;
        $output .= $theme->color('status_bg');
        $output .= ' ' x $remaining if $remaining > 0;

        # Open File pill
        if ($nerd_font) {
            $output .= $theme->color('status_bg') . $theme->color('pill_palette_edge');
            $output .= $round_l;
        }
        $output .= $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
        $output .= $open_text;
        if ($nerd_font) {
            $output .= $theme->color('status_bg') . $theme->color('pill_palette_edge');
            $output .= $round_r;
        }
        push @buttons, {
            x_start    => $cols - $right_width + 1,
            x_end      => $cols - $right_width + $open_width,
            command_id => 'open_file',
        };

        $output .= $theme->color('status_bg') . ' ';  # gap between pills

        # Palette trigger with rounded caps
        if ($nerd_font) {
            $output .= $theme->color('status_bg') . $theme->color('pill_palette_edge');
            $output .= $round_l;
            $output .= $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
            $output .= $palette_text;
            $output .= $theme->color('status_bg') . $theme->color('pill_palette_edge');
            $output .= $round_r;
        } else {
            $output .= $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
            $output .= $palette_text;
        }
        push @buttons, {
            x_start    => $cols - $palette_width + 1,
            x_end      => $cols,
            command_id => 'open_palette',
        };

        $output .= CLEAR_LINE . RESET;
        $class->_set_status_buttons(\@buttons);
        return $output;
    }

    # === Document context: build pill-based status bar ===

    # 1. LEFT: Cursor position pill with ⌃G shortcut (always visible, fixed width)
    my $cursor_icon = Zepto::Chars->get('cursor_pos');
    my $goto_shortcut = "\x{2303}G";
    my $cursor_text;
    if ($doc && $view) {
        my $line = $view->cursor_line() + 1;
        my $col = $view->cursor_col() + 1;
        $cursor_text = "$cursor_icon $line:$col $goto_shortcut";
    } else {
        $cursor_text = "$cursor_icon 1:1 $goto_shortcut";
    }
    # Pad to minimum width so pill doesn't resize as cursor moves
    my $min_cursor_width = length($cursor_icon) + length($goto_shortcut) + 8;  # e.g. " 999:99 ⌃G"
    my $pad_needed = $min_cursor_width - length($cursor_text);
    $cursor_text .= ' ' x $pad_needed if $pad_needed > 0;

    $output .= $theme->color('status_pos_bg') . $theme->color('status_pos_fg');
    $output .= " $cursor_text ";
    my $left_width = length($cursor_text) + 2;
    push @buttons, {
        x_start    => 1,
        x_end      => $left_width,
        command_id => 'goto_line',
    };

    # Column mode indicator (inline, if active)
    if ($view && $view->column_select()) {
        my $col_text;
        if ($view->has_selection()) {
            my ($top, $left, $bottom, $right) = $view->column_selection();
            my $lines = $bottom - $top + 1;
            my $rect_cols = $right - $left;
            $col_text = $rect_cols > 0 ? "COL ${lines}\x{00D7}${rect_cols}" : "COL ${lines}";
        } else {
            $col_text = "COL";
        }
        $output .= $theme->color('column_indicator_bg') . $theme->color('column_indicator_fg');
        $output .= " $col_text ";
        $left_width += length($col_text) + 2;
    }

    my $round_l = Zepto::Chars->get('round_left');
    my $round_r = Zepto::Chars->get('round_right');

    if ($nerd_font) {
        $output .= $theme->color('status_bg') . $theme->color('status_pos_edge');
        $output .= $round_r;
        $left_width += 1;
    }

    # 2. RIGHT: Open File + Palette trigger pills (always visible, rightmost)
    my $open_icon = Zepto::Chars->get('folder_open');
    my $open_text = " $open_icon Open \x{2303}O ";
    my $open_total_width = length($open_text) + ($nerd_font ? 2 : 0);

    my $palette_icon = Zepto::Chars->get('palette');
    my $palette_text = " $palette_icon Commands \x{2303}\x{2423} ";
    my $palette_text_width = length($palette_text);
    # Total palette width includes the round caps (left + right)
    my $palette_total_width = $palette_text_width + ($nerd_font ? 2 : 0);

    my $right_total_width = $open_total_width + 1 + $palette_total_width;  # +1 for gap

    # 3. CENTER: Priority-based pills
    my $editor = $ui->{editor};
    # No trailing transition cost — each pill is self-contained with its own caps
    # -2 accounts for gap before first pill and after cursor pill
    my $available = $cols - $left_width - $right_total_width - 2;
    $available = 0 if $available < 0;

    # Collect pills sorted by priority
    my @candidates;
    if ($editor) {
        my @cmds = Zepto::CommandRegistry->commands_for_status_bar('document', $cols, $editor);
        for my $cmd (@cmds) {
            my $icon = Zepto::Chars->get($cmd->{icon} // 'menu');
            my $shortcut = $cmd->{shortcut} // '';
            my ($fg, $bg, $edge);

            if ($cmd->{type} eq 'toggle') {
                my $state = Zepto::CommandRegistry->get_toggle_state($cmd, $editor);
                my $state_display = Zepto::CommandRegistry->get_toggle_display($cmd, $editor);

                # Determine effective on/off (handle theme specially)
                my $is_on = $state ? 1 : 0;
                if ($cmd->{pref} && $cmd->{pref} eq 'theme') {
                    $is_on = 1;  # Theme is always "active"
                }

                if ($is_on) {
                    $fg = 'pill_toggle_on_fg';
                    $bg = 'pill_toggle_on_bg';
                    $edge = 'pill_toggle_on_edge';
                } else {
                    $fg = 'pill_toggle_off_fg';
                    $bg = 'pill_toggle_off_bg';
                    $edge = 'pill_toggle_off_edge';
                }

                # Diff pill: color based on VCS status of current line
                if ($cmd->{id} eq 'toggle_diff' && $doc && $view) {
                    my $line = $view->cursor_line();
                    my $vcs_status = $doc->vcs_change_status($line);
                    my $del_status = $doc->vcs_deletion_status($line);
                    if ($vcs_status && $vcs_status eq 'added') {
                        $fg = 'pill_diff_added_fg';
                        $bg = 'pill_diff_added_bg';
                        $edge = 'pill_diff_added_edge';
                    } elsif ($vcs_status && ($vcs_status eq 'modified' || $vcs_status eq 'modified_whitespace')) {
                        $fg = 'pill_diff_modified_fg';
                        $bg = 'pill_diff_modified_bg';
                        $edge = 'pill_diff_modified_edge';
                    } elsif ($del_status) {
                        $fg = 'pill_diff_deleted_fg';
                        $bg = 'pill_diff_deleted_bg';
                        $edge = 'pill_diff_deleted_edge';
                    }
                    # else: keep default on/off colors (grey = no change)
                }

                my $label = $cmd->{label};
                if ($state_display ne '' && $state_display ne 'on' && $state_display ne 'off') {
                    $label .= ":$state_display";
                }

                my $text = "$icon $label $shortcut";
                my $pill_width = length($text) + 2;

                push @candidates, {
                    cmd      => $cmd,
                    text     => $text,
                    icon     => $icon,
                    label    => $label,
                    shortcut => $shortcut,
                    fg       => $fg,
                    bg       => $bg,
                    edge     => $edge,
                    width    => $pill_width,
                    priority => $cmd->{priority},
                    is_on    => $is_on,
                };
            }
            elsif ($cmd->{type} eq 'action') {
                my $label = $cmd->{label};
                my $text = "$icon $label $shortcut";
                my $pill_width = length($text) + 2;

                push @candidates, {
                    cmd      => $cmd,
                    text     => $text,
                    icon     => $icon,
                    label    => $label,
                    shortcut => $shortcut,
                    fg       => 'pill_action_fg',
                    bg       => 'pill_action_bg',
                    edge     => 'pill_action_edge',
                    width    => $pill_width,
                    priority => $cmd->{priority},
                };
            }
        }
    }

    # Greedily fit pills into available space
    my @pills_to_render;
    my $used = 0;
    for my $pill (@candidates) {
        # Each pill costs: content + caps (2 if nerd font) + 1 space gap
        my $pw = $pill->{width} + ($nerd_font ? 3 : 1);
        last if $used + $pw > $available;
        push @pills_to_render, $pill;
        $used += $pw;
    }

    # Render center pills with rounded caps
    # Add gap between cursor pill and first center pill (matching between-pill gaps)
    my $center_col = $left_width + 1;
    if (@pills_to_render) {
        $output .= $theme->color('status_bg') . ' ';
        $center_col += 1;
    }
    for my $i (0 .. $#pills_to_render) {
        my $pill = $pills_to_render[$i];

        if ($nerd_font) {
            # Left round cap
            $output .= $theme->color('status_bg') . $theme->color($pill->{edge});
            $output .= $round_l;
            $center_col += 1;
        }

        $output .= $theme->color($pill->{bg}) . $theme->color($pill->{fg});
        $output .= " $pill->{text} ";
        push @buttons, {
            x_start    => $center_col,
            x_end      => $center_col + $pill->{width} - 1,
            command_id => $pill->{cmd}{id},
        };
        $center_col += $pill->{width};

        if ($nerd_font) {
            # Right round cap
            $output .= $theme->color('status_bg') . $theme->color($pill->{edge});
            $output .= $round_r;
            $center_col += 1;
        }

        # Gap between pills
        $output .= $theme->color('status_bg') . ' ';
        $center_col += 1;
    }

    # Middle fill
    my $remaining = $cols - $center_col - $right_total_width + 1;
    $remaining = 0 if $remaining < 0;
    $output .= $theme->color('status_bg');
    $output .= ' ' x $remaining if $remaining > 0;

    # Open File pill
    if ($nerd_font) {
        $output .= $theme->color('status_bg') . $theme->color('pill_palette_edge');
        $output .= $round_l;
    }
    $output .= $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
    $output .= $open_text;
    if ($nerd_font) {
        $output .= $theme->color('status_bg') . $theme->color('pill_palette_edge');
        $output .= $round_r;
    }
    push @buttons, {
        x_start    => $cols - $right_total_width + 1,
        x_end      => $cols - $right_total_width + $open_total_width,
        command_id => 'open_file',
    };

    $output .= $theme->color('status_bg') . ' ';  # gap between pills

    # Palette trigger pill (rightmost) with rounded caps
    if ($nerd_font) {
        $output .= $theme->color('status_bg') . $theme->color('pill_palette_edge');
        $output .= $round_l;
    }
    $output .= $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
    $output .= $palette_text;
    if ($nerd_font) {
        $output .= $theme->color('status_bg') . $theme->color('pill_palette_edge');
        $output .= $round_r;
    }
    push @buttons, {
        x_start    => $cols - $palette_total_width + 1,
        x_end      => $cols,
        command_id => 'open_palette',
    };

    $output .= CLEAR_LINE . RESET;
    $class->_set_status_buttons(\@buttons);

    return $output;
}

# Render dialog box
sub _render_dialog {
    my ($class, $theme, $dialog, $total_rows, $total_cols) = @_;

    my $output = '';

    my $title = $dialog->{title} // 'Dialog';
    my $prompt = $dialog->{prompt} // '';
    my $value = $dialog->{value} // '';
    my $cursor_pos = $dialog->{cursor} // length($value);

    # Dialog dimensions
    my $dialog_width = DIALOG_WIDTH;
    $dialog_width = $total_cols - 4 if $dialog_width > $total_cols - 4;
    my $dialog_height = DIALOG_HEIGHT;

    # Center dialog
    my $x = int(($total_cols - $dialog_width) / 2);
    my $y = int(($total_rows - $dialog_height) / 2);
    $x = 1 if $x < 1;
    $y = 1 if $y < 1;

    # Get box drawing characters (rounded when nerd font enabled)
    my $box_tl = Zepto::Chars->get('box_tl');
    my $box_tr = Zepto::Chars->get('box_tr');
    my $box_bl = Zepto::Chars->get('box_bl');
    my $box_br = Zepto::Chars->get('box_br');
    my $box_h = Zepto::Chars->get('box_h');
    my $box_v = Zepto::Chars->get('box_v');

    # Draw dialog box
    $output .= $theme->color('dialog_bg');
    $output .= $theme->color('dialog_fg');

    # Top border
    $output .= _move_to($y, $x);
    $output .= $theme->color('dialog_border');
    $output .= $box_tl;
    $output .= $box_h x ($dialog_width - 2);
    $output .= $box_tr;

    # Title row
    $output .= _move_to($y + 1, $x);
    $output .= $theme->color('dialog_bg') . $theme->color('dialog_fg');
    $output .= $box_v;
    my $title_text = " $title ";
    my $title_pad = $dialog_width - 2 - length($title_text);
    $output .= $title_text . (' ' x $title_pad);
    $output .= $box_v;

    # Prompt row
    $output .= _move_to($y + 2, $x);
    $output .= $box_v;
    my $prompt_text = " $prompt";
    if (length($prompt_text) > $dialog_width - 4) {
        $prompt_text = substr($prompt_text, 0, $dialog_width - 4);
    }
    $output .= $prompt_text . (' ' x ($dialog_width - 2 - length($prompt_text)));
    $output .= $box_v;

    # Input row
    $output .= _move_to($y + 3, $x);
    $output .= $box_v . " ";
    $output .= $theme->color('dialog_input_bg');
    $output .= $theme->color('dialog_input_fg');

    my $input_width = $dialog_width - 4;
    my $display_value = $value;
    if (length($display_value) > $input_width) {
        $display_value = substr($display_value, length($display_value) - $input_width);
    }
    $output .= $display_value;
    $output .= ' ' x ($input_width - length($display_value));

    $output .= $theme->color('dialog_bg') . $theme->color('dialog_fg');
    $output .= " " . $box_v;

    # Bottom border
    $output .= _move_to($y + 4, $x);
    $output .= $theme->color('dialog_border');
    $output .= $box_bl;
    $output .= $box_h x ($dialog_width - 2);
    $output .= $box_br;

    $output .= RESET;

    return $output;
}

# Calculate screen position for cursor
sub _cursor_screen_pos {
    my ($class, $view, $gutter_width, $doc, $tree_width) = @_;
    $tree_width //= 0;

    my $cursor_line = $view->cursor_line();
    my $cursor_col = $view->cursor_col();
    my $scroll_line = $view->scroll_line();
    my $scroll_col = $view->scroll_col();

    # Convert character position to visual column (accounting for tabs)
    my $cursor_line_content = ($doc && $cursor_line < $doc->line_count())
        ? $doc->get_line_content($cursor_line)
        : '';
    my $visual_cursor_col = _char_to_visual_col($cursor_line_content, $cursor_col);

    # Text starts at row 3 (after tab bar at 1, ruler at 2)
    my $row_offset = 3;

    # Account for word wrap via WrapMap
    my $wm = $view->wrap_map();
    if ($wm) {
        my ($vrow, $vcol) = $wm->doc_to_visual($cursor_line, $cursor_col, $view->cursor_affinity());
        my $scroll_vrow = $view->scroll_visual_row();
        my $screen_row = $vrow - $scroll_vrow + $row_offset;
        my $screen_col = $vcol + $tree_width + $gutter_width + 1;
        return ($screen_row, $screen_col);
    }

    # Account for expanded hunk rows via LineMap
    my $lm = $view->line_map();
    my $screen_row;
    if ($lm && $lm->has_expanded_hunks()) {
        my $cursor_display = $lm->doc_line_to_display($cursor_line);
        my $scroll_display = $lm->scroll_display_start($scroll_line);
        $screen_row = $cursor_display - $scroll_display + $row_offset;
    } else {
        $screen_row = $cursor_line - $scroll_line + $row_offset;
    }
    my $screen_col = $visual_cursor_col - $scroll_col + $tree_width + $gutter_width + 1;  # +1 for 1-indexed

    return ($screen_row, $screen_col);
}

# =============================================================================
# Prompt Rendering (status bar prompt with clickable options)
# =============================================================================

{
    my $_prompt_buttons = [];
    sub _set_prompt_buttons { shift; $_prompt_buttons = shift; }
    sub get_prompt_buttons { return @{$_prompt_buttons}; }
}

# =============================================================================
# Footer Input Rendering (text input in status bar)
# =============================================================================

sub _render_footer_input {
    my ($class, $theme, $input, $cols) = @_;

    my $output = '';
    $output .= $theme->color('status_bg') . $theme->color('status_fg');

    my $prompt = $input->{prompt} // '';
    my $widget = $input->{widget};
    my $hint   = $input->{hint} // '';
    my $input_id = $input->{id} // '';

    # For goto_line: render as pill-style input with cursor icon
    my $prompt_str;
    if ($input_id eq 'goto_line') {
        my $cursor_icon = Zepto::Chars->get('cursor_pos');
        $output .= $theme->color('status_pos_bg') . $theme->color('status_pos_fg');
        $prompt_str = " $cursor_icon ";
    } else {
        $prompt_str = ' ' . $prompt . ' ';
    }
    $output .= $prompt_str;

    # Input field with distinct background
    $output .= $theme->color('dialog_input_bg');
    $output .= $theme->color('dialog_input_fg');

    # Calculate width for input field
    my $prompt_len = length($prompt_str);
    my $hint_str = $hint ? ($input_id eq 'goto_line' ? "  $hint" : " ($hint)") : '';
    my $hint_len = length($hint_str);
    my $input_width;
    if ($input->{wide}) {
        # Use most available space for the input field
        $input_width = $cols - $prompt_len - $hint_len - 2;
        $input_width = 20 if $input_width < 20;
    } elsif ($input_id eq 'goto_line') {
        $input_width = 10;
    } else {
        $input_width = 12;
    }

    # Get viewport (handles overflow scrolling)
    my $vp = $widget ? $widget->viewport($input_width) : { display_text => ($input->{value} // ''), sel_start_in_view => undef, sel_end_in_view => undef };
    my $display_value = $vp->{display_text};

    # Render with selection highlight
    my $sel_s = $vp->{sel_start_in_view};
    my $sel_e = $vp->{sel_end_in_view};
    if (defined $sel_s) {
        my $input_bg = $theme->color('dialog_input_bg');
        my $input_fg = $theme->color('dialog_input_fg');
        my $sel_bg   = $theme->color('selection_bg');
        my $sel_fg   = $theme->color('selection_fg');
        if ($sel_s > 0) {
            $output .= substr($display_value, 0, $sel_s);
        }
        $output .= $sel_bg . $sel_fg;
        $output .= substr($display_value, $sel_s, $sel_e - $sel_s);
        $output .= $input_bg . $input_fg;
        if ($sel_e < length($display_value)) {
            $output .= substr($display_value, $sel_e);
        }
    } else {
        $output .= $display_value;
    }

    # Fill remaining input area
    my $fill = $input_width - length($display_value);
    $output .= ' ' x $fill if $fill > 0;

    # Display hint in dimmed text
    $output .= $theme->color('status_bg');
    if ($hint) {
        $output .= $theme->color('status_dim');
        $output .= $hint_str;
    }

    # Pad rest of status bar
    my $remaining = $cols - $prompt_len - $input_width - $hint_len;
    $output .= ' ' x $remaining if $remaining > 0;

    $output .= CLEAR_LINE;
    $output .= RESET;

    return $output;
}

# =============================================================================
# Find Bar Rendering (incremental search in status bar)
# =============================================================================

# Colorize regex find input: highlight () capture groups with distinct colors
# Group numbers are assigned left-to-right by opening paren (matching Perl semantics)
sub _colorize_find_input {
    my ($class, $theme, $text, $default_fg) = @_;

    my $output = '';
    my $len = length($text);
    my $group_num = 0;       # Next group number to assign
    my @group_stack;         # Stack of active group numbers (for nesting)
    my $i = 0;

    while ($i < $len) {
        my $ch = substr($text, $i, 1);

        # Skip escaped characters
        if ($ch eq '\\' && $i + 1 < $len) {
            $output .= substr($text, $i, 2);
            $i += 2;
            next;
        }

        # Skip character classes
        if ($ch eq '[') {
            my $start = $i;
            $i++;
            $i++ if $i < $len && substr($text, $i, 1) eq '^';
            $i++ if $i < $len && substr($text, $i, 1) eq ']';
            while ($i < $len && substr($text, $i, 1) ne ']') {
                $i++ if substr($text, $i, 1) eq '\\';
                $i++;
            }
            $i++ if $i < $len;  # Skip closing ]
            $output .= substr($text, $start, $i - $start);
            next;
        }

        if ($ch eq '(') {
            # Determine if this is a capturing group
            my $is_capturing = 1;
            if ($i + 1 < $len && substr($text, $i + 1, 1) eq '?') {
                $is_capturing = 0;
                # Named capture (?<name>...) IS capturing
                if ($i + 2 < $len && substr($text, $i + 2, 1) eq '<'
                    && $i + 3 < $len && substr($text, $i + 3, 1) =~ /[A-Za-z_]/) {
                    $is_capturing = 1;
                }
                # (?P<name>...) IS capturing
                elsif ($i + 2 < $len && substr($text, $i + 2, 1) eq 'P'
                    && $i + 3 < $len && substr($text, $i + 3, 1) eq '<') {
                    $is_capturing = 1;
                }
            }

            if ($is_capturing) {
                $group_num++;
                my $color_idx = (($group_num - 1) % 4) + 1;
                my $color = $theme->color("capture_group_$color_idx");
                push @group_stack, { num => $group_num, color => $color };
                $output .= $color . $ch;
            } else {
                # Non-capturing group: push placeholder
                push @group_stack, { num => 0, color => undef };
                $output .= $ch;
            }
            $i++;
            next;
        }

        if ($ch eq ')' && @group_stack) {
            my $entry = pop @group_stack;
            if ($entry->{color}) {
                $output .= $entry->{color} . $ch;
            } else {
                $output .= $ch;
            }
            # Restore parent group color or default
            if (@group_stack && $group_stack[-1]{color}) {
                $output .= $group_stack[-1]{color};
            } else {
                $output .= $default_fg;
            }
            $i++;
            next;
        }

        # Regular character: use current group's color
        if (@group_stack && $group_stack[-1]{color}) {
            # Already in a colored group, color is set
        }
        $output .= $ch;
        $i++;
    }

    # Restore default color
    $output .= $default_fg;
    return $output;
}

# Colorize replace input: highlight $N tokens with capture group colors
sub _colorize_replace_input {
    my ($class, $theme, $text, $default_fg, $capture_count) = @_;

    my $output = '';
    my $len = length($text);
    my $i = 0;

    while ($i < $len) {
        my $ch = substr($text, $i, 1);

        if ($ch eq '$' && $i + 1 < $len) {
            my $next = substr($text, $i + 1, 1);

            if ($next eq '$') {
                # $$ escape
                $output .= '$$';
                $i += 2;
                next;
            }

            if ($next =~ /[0-9]/) {
                # Collect consecutive digits
                my $num_str = '';
                my $j = $i + 1;
                while ($j < $len && substr($text, $j, 1) =~ /[0-9]/) {
                    $num_str .= substr($text, $j, 1);
                    $j++;
                }
                my $num = int($num_str);
                my $token = '$' . $num_str;

                if ($num == 0) {
                    # $0 = full match, use dim color
                    $output .= $theme->color('status_dim') . $token . $default_fg;
                } elsif ($num <= $capture_count) {
                    # $N within range: use group color
                    my $color_idx = (($num - 1) % 4) + 1;
                    $output .= $theme->color("capture_group_$color_idx") . $token . $default_fg;
                } else {
                    # Beyond capture count: no special color
                    $output .= $token;
                }
                $i = $j;
                next;
            }
        }

        $output .= $ch;
        $i++;
    }

    return $output;
}

sub _render_find_bar {
    my ($class, $theme, $find, $cols) = @_;

    my $output = '';
    $output .= $theme->color('status_bg') . $theme->color('status_fg');

    my $value = $find->{value} // '';
    my $regex_on = $find->{regex} // 0;
    my $case_on = $find->{case} // 0;
    my $replace_value = $find->{replace_value} // '';
    my $replace_all = $find->{replace_all} // 1;
    my $focus = $find->{focus} // 'find';
    my $is_replacing = $find->{is_replacing} // 0;
    my $replace_progress = $find->{replace_progress} // 0;
    my $replace_total = $find->{replace_total} // 0;
    my $current = $find->{current} // 0;
    my $capture_count = $find->{capture_count} // 0;

    # Match count text
    my $match_count = $find->{match_count} // 0;
    my $is_searching = $find->{is_searching} // 0;
    my $match_text;
    if ($is_replacing) {
        $match_text = "Replacing $replace_progress/$replace_total...";
    } elsif ($match_count == 0) {
        $match_text = length($value) ? 'No matches' : '';
    } else {
        $match_text = ($current + 1) . ' of ' . $match_count;
        $match_text .= '...' if $is_searching;
    }

    # Rounded pill characters (nerd font or space fallback)
    my $rl = Zepto::Chars->get('round_left');
    my $rr = Zepto::Chars->get('round_right');

    # Build capture hint string (e.g. "$0 $1 $2") for status bar
    my $capture_hint = '';
    if ($regex_on) {
        $capture_hint = '$0';
        for my $i (1 .. $capture_count) {
            $capture_hint .= " \$$i";
        }
    }
    my $capture_hint_width = length($capture_hint) ? length($capture_hint) + 1 : 0;  # +1 for space

    # Fixed widths for buttons/toggles on right side
    # ".* ^R" (9+1) + "Aa ^C" (9+1) + "X Esc" (9+1) + "✓ Enter" (11) + spaces
    my $right_side_width = 45 + length($match_text) + $capture_hint_width;

    # Calculate input field widths
    my $available = $cols - 2 - 5 - 1 - 8 - 1 - $right_side_width;  # " Find:" + "Replace:" + spaces
    my $input_width = int($available / 2);
    $input_width = 8 if $input_width < 8;
    $input_width = 40 if $input_width > 40;  # Cap at reasonable width

    my $content = '';
    my $x = 1;  # Track position for click regions

    # Leading space
    $content .= ' ';
    $x++;

    # Find label
    $content .= 'Find:';
    $x += 5;

    # Find input field (clickable)
    my $find_field_start = $x;
    my $find_bg_color = ($focus eq 'find')
        ? $theme->color('dialog_input_bg') : $theme->color('menu_pill_bg');
    my $find_fg_color = ($focus eq 'find')
        ? $theme->color('dialog_input_fg') : $theme->color('menu_pill_text');
    $content .= $find_bg_color . $find_fg_color;
    my ($display_value, $find_sel_s, $find_sel_e);
    if (my $w = $find->{find_widget}) {
        my $vp = $w->viewport($input_width);
        $display_value = $vp->{display_text};
        $find_sel_s    = $vp->{sel_start_in_view};
        $find_sel_e    = $vp->{sel_end_in_view};
    } else {
        $display_value = $value;
        if (length($display_value) > $input_width) {
            $display_value = substr($display_value, length($display_value) - $input_width);
        }
        $find_sel_s = undef;
        $find_sel_e = undef;
    }
    if (defined $find_sel_s) {
        my $sel_bg = $theme->color('selection_bg');
        my $sel_fg = $theme->color('selection_fg');
        $content .= substr($display_value, 0, $find_sel_s) if $find_sel_s > 0;
        $content .= $sel_bg . $sel_fg;
        $content .= substr($display_value, $find_sel_s, $find_sel_e - $find_sel_s);
        $content .= $find_bg_color . $find_fg_color;
        $content .= substr($display_value, $find_sel_e) if $find_sel_e < length($display_value);
    } elsif ($regex_on && $capture_count > 0) {
        # Color capture groups in the find input
        $content .= $class->_colorize_find_input(
            $theme, $display_value, $find_fg_color);
    } else {
        $content .= $display_value;
    }
    $content .= $find_bg_color . $find_fg_color;
    $content .= ' ' x ($input_width - length($display_value));
    $x += $input_width;
    
    $content .= $theme->color('status_bg') . $theme->color('status_fg');
    $content .= ' ';
    $x++;

    # Replace label
    $content .= 'Replace:';
    $x += 8;

    # Replace input field (clickable)
    my $replace_field_start = $x;
    my $replace_bg_color = ($focus eq 'replace')
        ? $theme->color('dialog_input_bg') : $theme->color('menu_pill_bg');
    my $replace_fg_color = ($focus eq 'replace')
        ? $theme->color('dialog_input_fg') : $theme->color('menu_pill_text');
    $content .= $replace_bg_color . $replace_fg_color;
    my ($replace_display, $rep_sel_s, $rep_sel_e);
    if (my $w = $find->{replace_widget}) {
        my $vp = $w->viewport($input_width);
        $replace_display = $vp->{display_text};
        $rep_sel_s       = $vp->{sel_start_in_view};
        $rep_sel_e       = $vp->{sel_end_in_view};
    } else {
        $replace_display = $replace_value;
        if (length($replace_display) > $input_width) {
            $replace_display = substr($replace_display, length($replace_display) - $input_width);
        }
        $rep_sel_s = undef;
        $rep_sel_e = undef;
    }
    if (defined $rep_sel_s) {
        my $sel_bg = $theme->color('selection_bg');
        my $sel_fg = $theme->color('selection_fg');
        $content .= substr($replace_display, 0, $rep_sel_s) if $rep_sel_s > 0;
        $content .= $sel_bg . $sel_fg;
        $content .= substr($replace_display, $rep_sel_s, $rep_sel_e - $rep_sel_s);
        $content .= $replace_bg_color . $replace_fg_color;
        $content .= substr($replace_display, $rep_sel_e) if $rep_sel_e < length($replace_display);
    } elsif ($regex_on && $capture_count > 0) {
        # Color $N tokens in the replace input
        $content .= $class->_colorize_replace_input(
            $theme, $replace_display, $replace_fg_color, $capture_count);
    } else {
        $content .= $replace_display;
    }
    $content .= $replace_bg_color . $replace_fg_color;
    $content .= ' ' x ($input_width - length($replace_display));
    $x += $input_width;
    
    $content .= $theme->color('status_bg') . $theme->color('status_fg');
    $content .= ' ';
    $x++;

    # Get icons for buttons
    my $check_icon = Zepto::Chars->get('check');
    my $times_icon = Zepto::Chars->get('times');

    # Regex toggle pill (clickable) - like menu buttons with icon and shortcut
    my $regex_start = $x;
    if ($regex_on) {
        $content .= $theme->color('status_bg') . $theme->color('menu_active_edge');
        $content .= $rl;
        $content .= $theme->color('menu_active_bg') . $theme->color('menu_active_text');
        $content .= ' .* ';
        $content .= $theme->color('status_dim') . Zepto::CommandRegistry::SYM_CTRL() . 'R';
        $content .= $theme->color('menu_active_text') . ' ';
        $content .= $theme->color('status_bg') . $theme->color('menu_active_edge');
        $content .= $rr;
    } else {
        $content .= $theme->color('status_bg') . $theme->color('menu_pill_edge');
        $content .= $rl;
        $content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
        $content .= ' .* ';
        $content .= $theme->color('status_dim') . Zepto::CommandRegistry::SYM_CTRL() . 'R';
        $content .= $theme->color('menu_pill_text') . ' ';
        $content .= $theme->color('status_bg') . $theme->color('menu_pill_edge');
        $content .= $rr;
    }
    $x += 9;  # pill edges (2) + " .* ^R " (7)

    $content .= $theme->color('status_bg') . $theme->color('status_fg');
    $content .= ' ';
    $x++;

    # Case toggle pill (clickable) - like menu buttons with icon and shortcut
    my $case_start = $x;
    if ($case_on) {
        $content .= $theme->color('status_bg') . $theme->color('menu_active_edge');
        $content .= $rl;
        $content .= $theme->color('menu_active_bg') . $theme->color('menu_active_text');
        $content .= ' Aa ';
        $content .= $theme->color('status_dim') . Zepto::CommandRegistry::SYM_CTRL() . 'C';
        $content .= $theme->color('menu_active_text') . ' ';
        $content .= $theme->color('status_bg') . $theme->color('menu_active_edge');
        $content .= $rr;
    } else {
        $content .= $theme->color('status_bg') . $theme->color('menu_pill_edge');
        $content .= $rl;
        $content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
        $content .= ' Aa ';
        $content .= $theme->color('status_dim') . Zepto::CommandRegistry::SYM_CTRL() . 'C';
        $content .= $theme->color('menu_pill_text') . ' ';
        $content .= $theme->color('status_bg') . $theme->color('menu_pill_edge');
        $content .= $rr;
    }
    $x += 9;  # pill edges (2) + " Aa ^C " (7)

    $content .= $theme->color('status_bg') . $theme->color('status_fg');
    $content .= ' ';
    $x++;

    # Cancel button pill (clickable) - with X icon
    my $cancel_start = $x;
    $content .= $theme->color('status_bg') . $theme->color('menu_pill_edge');
    $content .= $rl;
    $content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
    $content .= " $times_icon ";
    $content .= $theme->color('status_dim') . 'Esc';
    $content .= $theme->color('menu_pill_text') . ' ';
    $content .= $theme->color('status_bg') . $theme->color('menu_pill_edge');
    $content .= $rr;
    $x += 9;  # pill edges (2) + " X Esc " (7)

    $content .= $theme->color('status_bg') . $theme->color('status_fg');
    $content .= ' ';
    $x++;

    # OK button pill (clickable) - active style with check icon
    my $ok_start = $x;
    $content .= $theme->color('status_bg') . $theme->color('menu_active_edge');
    $content .= $rl;
    $content .= $theme->color('menu_active_bg') . $theme->color('menu_active_text');
    $content .= " $check_icon ";
    $content .= $theme->color('status_dim') . 'Enter';
    $content .= $theme->color('menu_active_text') . ' ';
    $content .= $theme->color('status_bg') . $theme->color('menu_active_edge');
    $content .= $rr;
    $x += 11;  # pill edges (2) + " ✓ Enter " (9)
    
    $content .= $theme->color('status_bg') . $theme->color('status_fg');

    # Calculate visible width (strip ANSI codes)
    my $visible = $content;
    $visible =~ s/\x1b\[[0-9;]*m//g;
    my $visible_width = length($visible);

    # Add padding, capture hint, and match text
    my $padding_needed = $cols - $visible_width - length($match_text) - $capture_hint_width - 1;
    $padding_needed = 1 if $padding_needed < 1;
    $content .= ' ' x $padding_needed;

    # Render capture hint with colored $N tokens
    if ($capture_hint_width > 0) {
        # $0 in dim (no specific group color)
        $content .= $theme->color('status_dim') . '$0';
        # $1, $2, ... in their group colors
        for my $i (1 .. $capture_count) {
            $content .= ' ';
            my $color_idx = (($i - 1) % 4) + 1;
            $content .= $theme->color("capture_group_$color_idx");
            $content .= "\$$i";
        }
        $content .= $theme->color('status_fg') . ' ';
    }

    $content .= $match_text;
    $content .= ' ';

    $output .= $content;
    $output .= CLEAR_LINE;
    $output .= RESET;

    return $output;
}

sub _render_prompt {
    my ($class, $theme, $prompt, $cols, $rows) = @_;

    my $output = '';
    my $bg = $theme->color('prompt_bg');
    my $fg = $theme->color('prompt_fg');
    $output .= $bg . $fg;

    my $text = $prompt->{text} // '';
    my @options = @{$prompt->{options} // []};

    my $rl = Zepto::Chars->get('round_left');
    my $rr = Zepto::Chars->get('round_right');
    my $nerd_font = Zepto::Chars->enabled();

    # Warning icon + prompt text
    my $warn_icon = Zepto::Chars->get('warning');
    $output .= " $warn_icon $text ";
    my $x = 3 + length($text) + 1;  # icon(2) + space + text + space

    # Track button positions for click handling
    my @buttons;

    # Render each option as a pill
    for my $opt (@options) {
        my $key = uc($opt->{key});
        my $label = $opt->{label};
        my $icon = $opt->{icon} // '';

        # Build pill interior: " icon Label KEY "
        my $pill_text = $icon ? " $icon $label " : " $label ";
        $pill_text .= "$key ";
        my $pill_width = length($pill_text) + ($nerd_font ? 2 : 0);

        my $btn_start = $x;

        if ($nerd_font) {
            $output .= $bg . $theme->color('prompt_pill_edge') . $rl;
            $x++;
        }
        $output .= $theme->color('prompt_pill_bg') . $theme->color('prompt_pill_fg');
        # Render label then dimmed key
        if ($icon) {
            $output .= " $icon $label ";
        } else {
            $output .= " $label ";
        }
        $output .= $fg . $key . $theme->color('prompt_pill_fg') . ' ';
        if ($nerd_font) {
            $output .= $bg . $theme->color('prompt_pill_edge') . $rr;
            $x++;
        }
        $x += length($pill_text);

        push @buttons, {
            key => lc($opt->{key}),
            x_start => $btn_start + 1,
            x_end => $x,
            y => $rows,
        };

        $output .= $bg . $fg . ' ';
        $x++;
    }

    # Pad to fill status bar
    my $padding = $cols - $x;
    $output .= $bg . ' ' x $padding if $padding > 0;

    $output .= CLEAR_LINE;
    $output .= RESET;

    $class->_set_prompt_buttons(\@buttons);

    return $output;
}

# =============================================================================
# File Picker Rendering
# =============================================================================

# =============================================================================
# Command Palette Rendering
# =============================================================================

sub _render_command_palette {
    my ($class, $theme, $palette, $total_rows, $total_cols) = @_;

    my $output = '';

    my $query    = $palette->{query} // '';
    my $cursor   = $palette->{cursor} // 0;
    my $scroll   = $palette->{scroll} // 0;
    my $filtered = $palette->{filtered} // [];
    my $editor   = $palette->{editor};

    # Palette dimensions — adapts to terminal width
    my $pal_width = $total_cols - 4;
    if ($total_cols >= 120) {
        $pal_width = 80 if $pal_width > 80;    # Wide terminal: moderately wider
    } else {
        $pal_width = 60 if $pal_width > 60;    # Standard: default width
    }
    $pal_width = 30 if $pal_width < 30;

    my $max_items = $total_rows - 6;
    $max_items = 5 if $max_items < 5;
    $max_items = 30 if $max_items > 30;

    my $item_count = scalar @$filtered;
    # Fixed height: always use max_items so palette doesn't resize when filtering
    my $visible_items = $max_items;

    # Palette height: border(1) + filter(1) + separator(1) + items + border(1)
    my $pal_height = 3 + $visible_items + 1;

    # Center palette
    my $x = int(($total_cols - $pal_width) / 2);
    my $y = int(($total_rows - $pal_height) / 2);
    $x = 1 if $x < 1;
    $y = 2 if $y < 2;

    # Update visible rows for scroll management (write back to editor via palette hash)
    if ($editor) {
        $editor->{palette_visible_rows} = $visible_items;
    }

    # Get box drawing characters
    my $box_tl = Zepto::Chars->get('box_tl');
    my $box_tr = Zepto::Chars->get('box_tr');
    my $box_bl = Zepto::Chars->get('box_bl');
    my $box_br = Zepto::Chars->get('box_br');
    my $box_h  = Zepto::Chars->get('box_h');
    my $box_v  = Zepto::Chars->get('box_v');
    my $ar     = Zepto::Chars->get('arrow_right');

    # Colors - reuse dropdown palette which is already themed
    my $bg        = $theme->color('dropdown_bg');
    my $fg        = $theme->color('dropdown_fg');
    my $sel_bg    = $theme->color('dropdown_selected_bg');
    my $sel_fg    = $theme->color('dropdown_selected_fg');
    my $border_fg = $theme->color('dropdown_border');
    my $shortcut_fg = $theme->color('dropdown_shortcut');

    # === Top border with title ===
    my $mode = $palette->{mode} // 'commands';
    my $title;
    if ($mode eq 'recent_files') {
        $title = " \x{2303}E Recent Files ";
    } elsif ($mode eq 'files') {
        $title = " \x{2303}O Open File ";
    } else {
        $title = " \x{2303}\x{2423} Commands ";
    }
    my $title_len = length($title);
    my $border_left = int(($pal_width - 2 - $title_len) / 2);
    $border_left = 0 if $border_left < 0;
    my $border_right = $pal_width - 2 - $border_left - $title_len;
    $border_right = 0 if $border_right < 0;

    $output .= _move_to($y, $x);
    $output .= $bg . $border_fg;
    $output .= $box_tl;
    $output .= $box_h x $border_left;
    $output .= $fg . $title;
    $output .= $border_fg;
    $output .= $box_h x $border_right;
    $output .= $box_tr;

    # === Filter input row ===
    $output .= _move_to($y + 1, $x);
    $output .= $bg . $border_fg . $box_v;

    my $filter_icon = Zepto::Chars->get('filter');
    my $inner_width = $pal_width - 2;  # inside the box borders

    # Input area: icon + space + query + padding
    $output .= $bg . $fg;
    $output .= " $filter_icon ";
    my $input_area = $inner_width - 4;  # -4 for " icon space" + trailing space
    my ($display_query, $pal_sel_s, $pal_sel_e);
    if (my $w = $palette->{palette_widget}) {
        my $vp = $w->viewport($input_area);
        $display_query = $vp->{display_text};
        $pal_sel_s     = $vp->{sel_start_in_view};
        $pal_sel_e     = $vp->{sel_end_in_view};
    } else {
        $display_query = $query;
        if (length($display_query) > $input_area) {
            $display_query = substr($display_query, length($display_query) - $input_area);
        }
        $pal_sel_s = undef;
        $pal_sel_e = undef;
    }
    my $input_fg = $theme->color('dialog_input_fg');
    if (defined $pal_sel_s) {
        my $sel_bg = $theme->color('selection_bg');
        my $sel_fg = $theme->color('selection_fg');
        $output .= $input_fg;
        $output .= substr($display_query, 0, $pal_sel_s) if $pal_sel_s > 0;
        $output .= $sel_bg . $sel_fg;
        $output .= substr($display_query, $pal_sel_s, $pal_sel_e - $pal_sel_s);
        $output .= $bg . $input_fg;
        $output .= substr($display_query, $pal_sel_e) if $pal_sel_e < length($display_query);
        $output .= $fg;
    } else {
        $output .= $input_fg;
        $output .= $display_query;
        $output .= $fg;
    }
    my $qpad = $input_area - length($display_query);
    $output .= ' ' x $qpad if $qpad > 0;
    $output .= ' ';

    $output .= $border_fg . $box_v;

    # === Separator row ===
    $output .= _move_to($y + 2, $x);
    $output .= $bg . $border_fg;
    $output .= "\x{251C}";  # ├
    $output .= $box_h x ($pal_width - 2);
    $output .= "\x{2524}";  # ┤

    # === Item rows ===
    my @buttons;
    my $current_section = '';

    for my $vi (0 .. $visible_items - 1) {
        my $item_idx = $scroll + $vi;
        my $row_y = $y + 3 + $vi;

        $output .= _move_to($row_y, $x);
        $output .= $bg . $border_fg . $box_v;

        if ($item_idx < $item_count) {
            my $cmd = $filtered->[$item_idx];

            # Section header row
            if ($cmd->{_is_header}) {
                $output .= $bg . $shortcut_fg;
                my $header_label = "  \x{2500}\x{2500} " . $cmd->{label} . " ";
                my $header_pad = $inner_width - length($header_label);
                $header_pad = 0 if $header_pad < 0;
                $output .= $header_label;
                # Fill remaining space with light horizontal line
                $output .= "\x{2500}" x $header_pad if $header_pad > 0;
                $output .= $border_fg . $box_v;
                $output .= RESET;
                next;
            }

            my $is_selected = ($item_idx == $cursor);

            # Row background
            if ($is_selected) {
                $output .= $sel_bg . $sel_fg;
            } else {
                $output .= $bg . $fg;
            }

            # Selection indicator
            my $prefix = $is_selected ? ($ar . ' ') : '  ';
            $output .= $prefix;

            # Icon
            my $icon;
            if ($cmd->{_is_file}) {
                $icon = Zepto::Chars->file_icon($cmd->{_filename});
            } else {
                $icon = Zepto::Chars->get($cmd->{icon} // 'menu');
            }
            $output .= "$icon ";

            # Shortcut
            my $shortcut = $cmd->{shortcut} // '';
            my $shortcut_display = $shortcut;
            my $shortcut_width = length($shortcut_display);

            # Toggle state (right-aligned)
            my $toggle_text = '';
            if ($cmd->{type} eq 'toggle' && $editor) {
                my $state = Zepto::CommandRegistry->get_toggle_display($cmd, $editor);
                $toggle_text = "[$state]" if $state ne '';
            }
            my $toggle_width = length($toggle_text);

            # Label - fill remaining space
            my $label = $cmd->{label} // '';
            # Available: inner_width - 2(prefix) - 2(icon+space) - shortcut - toggle - spaces
            my $label_space = $inner_width - 2 - 2 - $shortcut_width - 1 - $toggle_width - 2;
            $label_space = 4 if $label_space < 4;

            if (length($label) > $label_space) {
                $label = substr($label, 0, $label_space - 1) . "\x{2026}";  # …
            }

            $output .= $label;
            my $label_pad = $label_space - length($label);
            $output .= ' ' x $label_pad if $label_pad > 0;
            $output .= ' ';

            # Shortcut (dimmed unless selected)
            if (!$is_selected) {
                $output .= $shortcut_fg;
            }
            $output .= $shortcut_display;

            # Toggle state
            if ($toggle_width > 0) {
                $output .= ' ';
                if ($is_selected) {
                    $output .= $toggle_text;
                } else {
                    $output .= $shortcut_fg . $toggle_text;
                }
            }

            # Pad to fill row
            my $content_len = 2 + 2 + length($label) + $label_pad + 1 + $shortcut_width + ($toggle_width > 0 ? 1 + $toggle_width : 0);
            my $row_pad = $inner_width - $content_len;
            if ($is_selected) {
                $output .= $sel_bg;
            } else {
                $output .= $bg;
            }
            $output .= ' ' x $row_pad if $row_pad > 0;

            # Store button region for click handling
            push @buttons, {
                y       => $row_y,
                x_start => $x + 1,
                x_end   => $x + $pal_width - 2,
                index   => $item_idx,
            };
        } else {
            # Empty row (fixed-height palette may have unfilled rows)
            $output .= $bg . (' ' x $inner_width);
        }

        $output .= $bg . $border_fg . $box_v;
        $output .= RESET;
    }

    # === Bottom border ===
    my $bottom_y = $y + 3 + $visible_items;
    $output .= _move_to($bottom_y, $x);
    $output .= $bg . $border_fg;
    $output .= $box_bl;

    # Bottom border content: item count hint
    my $count_label = $mode eq 'recent_files' ? 'files' : 'commands';
    my $count_text = " $item_count $count_label ";
    my $bottom_border_left = int(($pal_width - 2 - length($count_text)) / 2);
    $bottom_border_left = 0 if $bottom_border_left < 0;
    my $bottom_border_right = $pal_width - 2 - $bottom_border_left - length($count_text);
    $bottom_border_right = 0 if $bottom_border_right < 0;
    $output .= $box_h x $bottom_border_left;
    $output .= $fg . $count_text;
    $output .= $border_fg;
    $output .= $box_h x $bottom_border_right;
    $output .= $box_br;
    $output .= RESET;

    $class->_set_palette_buttons(\@buttons);
    $class->_set_palette_geometry({
        x => $x, y => $y, width => $pal_width,
        filter_row => $y + 1, filter_x_start => $x + 4,
        filter_input_width => $pal_width - 6,
    });

    return $output;
}

1;
