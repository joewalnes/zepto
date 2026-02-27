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
    MENU_DROPDOWN_WIDTH => 24,
    DIALOG_WIDTH       => 50,
    DIALOG_HEIGHT      => 5,
    MINIMAP_WIDTH      => 8,  # Must match Zepto::Minimap::MINIMAP_TOTAL_WIDTH
    TREE_INDENT_PER_LEVEL => 2,   # Must match Zepto::FileTree::INDENT_PER_LEVEL
    TREE_MAX_INDENT       => 16,  # Must match Zepto::FileTree::MAX_INDENT
};

# Menu definitions (single source of truth for menu names, order, and items)
our @MENU_DEFS = (
    { key => 'f', name => 'File',   icon => 'menu_file' },
    { key => 'e', name => 'Edit',   icon => 'menu_edit' },
    { key => 's', name => 'Search', icon => 'menu_search' },
    { key => 'v', name => 'View',   icon => 'menu_view' },
);

# Full menu item definitions - single source of truth for both rendering and execution
our %MENU_ITEMS = (
    f => [
        { label => 'New',         shortcut => 'Ctrl+N', action => 'new' },
        { label => 'Open',        shortcut => 'Ctrl+O', action => 'open' },
        { separator => 1 },
        { label => 'Save',        shortcut => 'Ctrl+S', action => 'save' },
        { label => 'Close Tab', shortcut => 'Ctrl+W', action => 'close_tab' },
        { separator => 1 },
        { label => 'Quit',        shortcut => 'Ctrl+Q', action => 'quit' },
    ],
    e => [
        { label => 'Undo',         shortcut => 'Ctrl+Z', action => 'undo' },
        { label => 'Redo',         shortcut => 'Ctrl+Y', action => 'redo' },
        { separator => 1 },
        { label => 'Cut',          shortcut => 'Ctrl+X', action => 'cut' },
        { label => 'Copy',         shortcut => 'Ctrl+C', action => 'copy' },
        { label => 'Paste',        shortcut => 'Ctrl+V', action => 'paste' },
        { separator => 1 },
        { label => "Move Up",      shortcut => "Alt+\x{2191}", action => 'move_line_up' },
        { label => "Move Down",    shortcut => "Alt+\x{2193}", action => 'move_line_down' },
        { label => "Dup Up",       shortcut => "Alt+\x{21E7}\x{2191}", action => 'dup_line_up' },
        { label => "Dup Down",     shortcut => "Alt+\x{21E7}\x{2193}", action => 'dup_line_down' },
        { separator => 1 },
        { label => 'Select All',   shortcut => 'Ctrl+A', action => 'select_all' },
    ],
    s => [
        { label => 'Find/Replace', shortcut => 'Ctrl+F', action => 'find' },
        { label => 'Go to Line',   shortcut => 'Ctrl+G', action => 'goto' },
    ],
    v => [
        { label => 'Toggle Theme', shortcut => 'Ctrl+T', action => 'toggle_theme' },
        { label => 'Powerline',    shortcut => 'Ctrl+P', action => 'toggle_powerline', toggle => 'powerline' },
        { label => 'Minimap',      shortcut => 'Alt+M',  action => 'toggle_minimap', toggle => 'show_minimap' },
        { label => 'File Tree',    shortcut => 'Ctrl+B', action => 'toggle_tree', toggle => 'show_tree' },
        { separator => 1 },
        { label => 'Next Tab',       shortcut => 'Alt+.',     action => 'next_tab' },
        { label => 'Prev Tab',       shortcut => 'Alt+,',     action => 'prev_tab' },
        { separator => 1 },
        { label => 'Toggle Diff',    shortcut => 'Alt+D',   action => 'toggle_diff' },
        { separator => 1 },
        { label => "Next Change",    shortcut => "Alt+N",   action => 'next_change' },
        { label => "Prev Change",    shortcut => "Alt+P",   action => 'prev_change' },
    ],
);

# Get menu item actions for a menu key (used by Menu.pm)
sub get_menu_actions {
    my ($class, $menu_key) = @_;
    my $items = $MENU_ITEMS{$menu_key} // [];
    return [ map { $_->{separator} ? '-' : $_->{action} } @$items ];
}

# Menu bar prefix width (menu pill + space)
# Format: ' ' + RL + ' ☰ esc ' + RR + ' ' = 11 chars
use constant MENU_ESC_PREFIX_WIDTH => 11;

# Tab width for visual rendering
use constant TAB_WIDTH => 4;

# Terminal display width of a single character.
# Returns 2 for wide chars (CJK, emoji), 0 for control/combining, 1 otherwise.
sub _char_display_width {
    my $ord = ord($_[0]);
    return 0 if $ord < 0x20;       # control chars
    return 1 if $ord < 0x1100;     # ASCII, Latin, Cyrillic, etc.
    return 2 if ($ord >= 0x1100 && $ord <= 0x115F)    # Hangul Jamo
             || ($ord >= 0x231A && $ord <= 0x23FF)    # Misc Technical (⌚ etc.)
             || ($ord >= 0x2600 && $ord <= 0x27BF)    # Misc Symbols, Dingbats (❌ etc.)
             || ($ord >= 0x2B50 && $ord <= 0x2B55)    # Stars
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
    $char_pos = $len if $char_pos > $len;

    for my $i (0 .. $char_pos - 1) {
        my $char = substr($text, $i, 1);
        if ($char eq "\t") {
            $visual_col += TAB_WIDTH - ($visual_col % TAB_WIDTH);
        } else {
            $visual_col++;
        }
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

    # Visual column is beyond end of line, return line length
    return $len;
}

# Menu bar buttons on the right side
our @MENU_BAR_BUTTONS = (
    { label => 'Files', key => '^B', action => 'toggle_tree', icon => 'folder' },
    { label => 'Open', key => '^O', action => 'open', icon => 'folder_open' },
    { label => 'Save', key => '^S', action => 'save', icon => 'save' },
    { label => 'Quit', key => '^Q', action => 'quit', icon => 'quit' },
);

# Calculate menu positions dynamically from menu definitions
# Returns hash: { f => { start => 0, end => 5, x => 1 }, ... }
sub get_menu_positions {
    my %positions;
    my $x = MENU_ESC_PREFIX_WIDTH;  # Account for menu icon prefix

    for my $menu (@MENU_DEFS) {
        # Pill format: RL + space + [icon + space] + Name + space + RR
        my $width = length($menu->{name}) + 4;  # edges + padding
        # Add icon width (always present - either powerline or bullet)
        if ($menu->{icon}) {
            $width += 2;  # icon (1 display char) + space
        }
        $positions{$menu->{key}} = {
            start => $x,                  # Start of clickable region (0-indexed)
            end   => $x + $width - 1,     # End of clickable region (0-indexed)
            x     => $x + 1,              # X position for dropdown (1-indexed for terminal)
        };
        $x += $width + 1;  # +1 for space between pills
    }

    return \%positions;
}

# Store and retrieve menu bar button positions for click handling
{
    my $_menu_bar_buttons = [];
    sub _set_menu_bar_buttons { shift; $_menu_bar_buttons = shift; }
    sub get_menu_bar_buttons { return @{$_menu_bar_buttons}; }
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
    my $gutter_width = $max_digits + 3;  # +3 for VCS (1) + badge chars (round_left + arrow_right = 2)
    $gutter_width = MIN_GUTTER_WIDTH + 1 if $gutter_width < MIN_GUTTER_WIDTH + 1;
    return $gutter_width;
}

# Calculate the minimap width for given parameters.
# Returns 0 if minimap should be hidden.
sub get_minimap_width {
    my ($class, $line_count, $text_height, $cols, $gutter_width, $prefs) = @_;
    return 0 unless $prefs && $prefs->show_minimap();
    return 0 unless $line_count > $text_height;
    my $tentative_text = $cols - $gutter_width - MINIMAP_WIDTH;
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
    my $highlighter = $args{highlighter};  # Optional syntax highlighter

    # Sync Chars module with prefs
    if ($prefs) {
        Zepto::Chars->set_enabled($prefs->powerline());
    }

    my $output = '';

    # Hide cursor during redraw to avoid flicker
    $output .= HIDE_CURSOR;

    # Move to top-left
    $output .= CURSOR_HOME;

    # Calculate layout
    my $menu_height = 1;
    my $tab_height = 1;
    my $ruler_height = 1;
    my $status_height = 1;
    my $text_height = $rows - $menu_height - $tab_height - $ruler_height - $status_height;
    $text_height = 1 if $text_height < 1;

    # Calculate gutter width based on line count
    my $line_count = $doc ? $doc->line_count() : 1;
    my $gutter_width = $class->get_gutter_width($line_count);

    # Determine minimap width
    my $show_minimap = $prefs && $prefs->show_minimap();
    my $minimap_width = 0;
    if ($show_minimap && $doc && $line_count > $text_height) {
        # Show minimap when document is taller than viewport
        my $tentative_text = $cols - $gutter_width - MINIMAP_WIDTH;
        if ($tentative_text >= MIN_TEXT_WIDTH) {
            $minimap_width = MINIMAP_WIDTH;
        }
    }

    # Calculate tree panel width (panel + border column)
    my $tree = $ui->{file_tree};
    my $tree_width = 0;
    if ($tree && $tree->panel_width() > 0) {
        my $tw = $tree->panel_width() + 1;  # +1 for border column
        my $remaining = $cols - $tw - $gutter_width - $minimap_width;
        if ($remaining >= MIN_TEXT_WIDTH) {
            $tree_width = $tw;
        }
    }

    my $text_width = $cols - $tree_width - $gutter_width - $minimap_width;
    $text_width = MIN_TEXT_WIDTH if $text_width < MIN_TEXT_WIDTH;

    # Render menu bar (row 1)
    $output .= _move_to(1, 1);
    $output .= $class->_render_menu_bar($theme, $cols, $ui);

    # Render tree panel (rows 2..N-1, left columns)
    # Tree starts at row 2 so it spans the full height below the menu bar
    if ($tree_width > 0) {
        my $tree_height = $text_height + 2;  # +2 for tab bar and ruler rows
        $output .= $class->_render_tree_panel(
            $tree, $tree_height, $theme, $tree_width, $ui
        );
    }

    # Render tab bar (row 2, right of tree)
    $output .= _move_to(2, $tree_width + 1);
    $output .= $class->_render_tab_bar($theme, $cols, $ui, $tree_width);

    # Render ruler bar (row 3, right of tree)
    $output .= _move_to(3, $tree_width + 1);
    $output .= $class->_render_ruler_bar($theme, $cols, $gutter_width, $view, $doc, $tree_width, $ui);

    # Render text area or file picker
    if ($ui->{file_picker}) {
        # File picker replaces the text area
        $output .= $class->_render_file_picker(
            $theme, $ui->{file_picker}, $text_height, $cols
        );
    } else {
        # Normal text area with line numbers (rows 4 to 4+text_height-1)
        $output .= $class->_render_text_area(
            $doc, $view, $theme,
            $text_height, $text_width, $gutter_width, $highlighter,
            $ui->{find_mode}, $minimap_width, $tree_width
        );
    }

    # Render status bar (last row) - prompt/footer_input/find replace normal content
    $output .= _move_to($rows, 1);
    if ($ui->{prompt}) {
        $output .= $class->_render_prompt(
            $theme, $ui->{prompt}, $cols, $rows
        );
    } elsif ($ui->{find_mode}) {
        $output .= $class->_render_find_bar(
            $theme, $ui->{find_mode}, $cols
        );
    } elsif ($ui->{footer_input}) {
        $output .= $class->_render_footer_input(
            $theme, $ui->{footer_input}, $cols
        );
    } else {
        # Compute contextual hint for status bar
        my ($status_hint, $hint_color);
        if ($tree && $tree->focused()) {
            # Tree focused: show tree-specific hints
            my $node = $tree->cursor_node();
            my $node_path = $node ? $node->{path} : '';
            $status_hint = "\x{2191}\x{2193} nav  \x{2190}\x{2192} fold  Enter open  { } resize  / filter  Esc back";
            $output .= $class->_render_status_bar(
                $doc, $view, $theme, $cols, $node_path, $status_hint, undef
            );
        } else {
            if ($doc && $view && !$message) {
                my $cl = $view->cursor_line();
                my $hunk_idx = $doc->vcs_hunk_at_line($cl);
                if (defined $hunk_idx) {
                    my $hunks = $doc->vcs_hunks();
                    my $h = $hunks->[$hunk_idx];
                    my $type = $h->{type} // 'modified';
                    if ($type eq 'added') {
                        $hint_color = $theme->color('vcs_added');
                    } elsif ($type eq 'deleted') {
                        $hint_color = $theme->color('vcs_deleted');
                    } else {
                        $hint_color = $theme->color('vcs_modified');
                    }
                    $status_hint = "Alt+D expand diff \x{00B7} Alt+N/P next/prev";
                }
            }
            $output .= $class->_render_status_bar(
                $doc, $view, $theme, $cols, $message, $status_hint, $hint_color
            );
        }
    }

    # Render dropdown menu if open
    if ($ui->{menu_open}) {
        $output .= $class->_render_dropdown(
            $theme, $ui, $cols, $prefs
        );
    }

    # Render dialog if open
    if ($ui->{dialog}) {
        $output .= $class->_render_dialog(
            $theme, $ui->{dialog}, $rows, $cols
        );
    }

    # Position cursor
    if ($ui->{dialog}) {
        # Dialogs position cursor themselves
        $output .= SHOW_CURSOR;
    } elsif ($ui->{file_picker}) {
        # Position cursor in file picker search input
        my $picker = $ui->{file_picker};
        my $query_len = length($picker->query() // '');
        $output .= _move_to(4, 4 + $query_len);  # Row 4, after "> "
        $output .= SHOW_CURSOR;
    } elsif ($ui->{footer_input}) {
        # Position cursor in footer input field
        my $input = $ui->{footer_input};
        my $prompt_len = length($input->{prompt} // '') + 2;  # +2 for leading/trailing space
        my $cursor_pos = $input->{cursor} // 0;
        $output .= _move_to($rows, $prompt_len + $cursor_pos + 1);
        $output .= SHOW_CURSOR;
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
            # Replace cursor position - handle text longer than field
            my $cursor_pos = $find->{replace_cursor} // 0;
            my $display_offset = 0;
            if (length($replace_value) > $input_width) {
                $display_offset = length($replace_value) - $input_width;
            }
            my $cursor_in_field = $cursor_pos - $display_offset;
            $cursor_in_field = 0 if $cursor_in_field < 0;
            $cursor_in_field = $input_width if $cursor_in_field > $input_width;
            # Replace field position: " Find:" (6) + input_width + " Replace:" (9)
            my $replace_start = 1 + 5 + $input_width + 1 + 8;
            $output .= _move_to($rows, $replace_start + $cursor_in_field + 1);
        } else {
            # Find cursor position - handle text longer than field
            my $cursor_pos = $find->{cursor} // 0;
            my $display_offset = 0;
            if (length($value) > $input_width) {
                $display_offset = length($value) - $input_width;
            }
            my $cursor_in_field = $cursor_pos - $display_offset;
            $cursor_in_field = 0 if $cursor_in_field < 0;
            $cursor_in_field = $input_width if $cursor_in_field > $input_width;
            # Find field starts at column 7 (" Find:")
            my $label_len = 6;  # "Find:"
            $output .= _move_to($rows, $label_len + $cursor_in_field + 1);
        }
        $output .= SHOW_CURSOR;
    } elsif ($ui->{menu_open}) {
        # Hide cursor when menu is open so it doesn't shine through
        $output .= HIDE_CURSOR;
    } elsif ($ui->{prompt}) {
        # Hide cursor during prompt - no text input
        $output .= HIDE_CURSOR;
    } elsif ($ui->{file_tree} && $ui->{file_tree}->focused()) {
        # Tree is focused — hide cursor (or show in filter input)
        if ($ui->{file_tree}->filter_active()) {
            my $filter_len = length($ui->{file_tree}->filter_query() // '');
            my $sticky_count = scalar @{$ui->{file_tree}->sticky_headers()};
            $output .= _move_to(2 + $sticky_count, 4 + $filter_len);  # tree starts at row 2, " / " = 3 chars prefix
            $output .= SHOW_CURSOR;
        } else {
            $output .= HIDE_CURSOR;
        }
    } elsif ($view && $doc) {
        # Position terminal cursor for editing
        my ($cursor_row, $cursor_col) = $class->_cursor_screen_pos(
            $view, $gutter_width, $menu_height, $doc, $tree_width
        );
        $output .= _move_to($cursor_row, $cursor_col);
        $output .= SHOW_CURSOR;
    }

    return $output;
}

# Render the menu bar
sub _render_menu_bar {
    my ($class, $theme, $cols, $ui) = @_;

    my $output = '';
    $output .= $theme->color('menu_bg') . $theme->color('menu_fg');

    # Left side: Menu icon as a subtle pill
    my $menu_icon = Zepto::Chars->get('menu');
    my $rl = Zepto::Chars->get('round_left');
    my $rr = Zepto::Chars->get('round_right');

    # Menu indicator pill
    $output .= ' ';
    $output .= $theme->color('menu_bg') . $theme->color('menu_pill_edge');
    $output .= $rl;
    $output .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
    $output .= " $menu_icon esc ";
    $output .= $theme->color('menu_bg') . $theme->color('menu_pill_edge');
    $output .= $rr;
    $output .= $theme->color('menu_fg') . ' ';

    my $x = MENU_ESC_PREFIX_WIDTH;

    # Menu names as rounded pills with icons
    # Reset colors before starting menu pills to ensure clean state
    $output .= RESET . $theme->color('menu_bg') . $theme->color('menu_fg');

    for my $menu (@MENU_DEFS) {
        my $is_active = ($ui->{menu_open} // '') eq $menu->{key};
        my $icon = $menu->{icon} ? Zepto::Chars->get($menu->{icon}) : '';
        my $icon_str = $icon ? "$icon " : '';
        my $content = " $icon_str$menu->{name} ";

        if ($is_active) {
            # Active menu: colored pill
            # Both edges: bg=menu bar, fg=pill interior (powerline chars fill with fg)
            $output .= $theme->color('menu_bg') . $theme->color('menu_active_edge');
            $output .= $rl;
            $output .= $theme->color('menu_active_bg') . $theme->color('menu_active_text');
            $output .= $content;
            $output .= $theme->color('menu_bg') . $theme->color('menu_active_edge');
            $output .= $rr;
            $output .= $theme->color('menu_fg');
        } else {
            # Inactive menu: subtle pill
            $output .= $theme->color('menu_bg') . $theme->color('menu_pill_edge');
            $output .= $rl;
            $output .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
            $output .= $content;
            $output .= $theme->color('menu_bg') . $theme->color('menu_pill_edge');
            $output .= $rr;
            $output .= $theme->color('menu_fg');
        }

        $output .= ' ';  # Space between pills
        # Width: pill chars (2) + space + [icon + space if present] + name + space + trailing space
        my $pill_width = length($menu->{name}) + 4;  # 2 edges + 2 spaces around name
        $pill_width += 2 if $icon;  # icon (1 display char) + space (always, not just powerline)
        $x += $pill_width + 1;  # +1 for space between pills
    }

    # Right side: Action buttons as rounded pills with icons + labels
    my @buttons_copy;
    my $buttons_width = 0;
    for my $btn (@MENU_BAR_BUTTONS) {
        # Get icon for button (always present, either powerline or bullet)
        my $icon = $btn->{icon} ? Zepto::Chars->get($btn->{icon}) : '';
        # Inner content: " icon label key " (3 template spaces + icon_str)
        my $icon_str = $icon ? "$icon " : '';
        my $btn_inner = " $icon_str$btn->{label} $btn->{key} ";
        # Display width: 3 (spaces in template) + label + key + icon(2 if present)
        my $inner_width = length($btn->{label}) + length($btn->{key}) + 3;
        $inner_width += 2 if $icon;  # icon (1) + space (1)
        # Total: rl(1) + inner + rr(1) + trailing_space(1)
        my $btn_width = $inner_width + 3;
        push @buttons_copy, {
            %$btn,
            inner => $btn_inner,
            width => $btn_width,
        };
        $buttons_width += $btn_width;
    }

    # Fill middle with spaces
    my $remaining = $cols - $x - $buttons_width;
    $output .= ' ' x $remaining if $remaining > 0;

    # Track button positions and render as pills
    my $btn_x = $cols - $buttons_width;
    for my $btn (@buttons_copy) {
        $btn->{x_start} = $btn_x;
        $btn->{x_end} = $btn_x + $btn->{width} - 2;  # -1 for trailing space
        $btn_x += $btn->{width};

        # Render button as pill (both edges: bg=menu, fg=pill interior)
        $output .= $theme->color('menu_bg') . $theme->color('menu_pill_edge');
        $output .= $rl;
        $output .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
        $output .= $btn->{inner};
        $output .= $theme->color('menu_bg') . $theme->color('menu_pill_edge');
        $output .= $rr;
        $output .= $theme->color('menu_fg') . ' ';
    }
    $class->_set_menu_bar_buttons(\@buttons_copy);

    # Reset before clear to show terminal default on right edge (consistent with text rows)
    $output .= RESET;
    $output .= CLEAR_LINE;

    return $output;
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

    # Fill remaining space with bar bg (underlined)
    my $remaining = $tab_cols - $x;
    if ($remaining > 0) {
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

    $output .= RESET;
    $output .= CLEAR_LINE;

    return $output;
}

# Render the text area with line numbers
sub _render_text_area {
    my ($class, $doc, $view, $theme, $height, $width, $gutter_width, $highlighter, $find_mode, $minimap_width, $tree_width) = @_;
    $minimap_width //= 0;
    $tree_width //= 0;

    my $output = '';

    return $output unless $doc && $view;

    my $scroll_line = $view->scroll_line();
    my $visible_start = $scroll_line;
    my $visible_end = $scroll_line + $height;

    # Get LineMap for inline diff expansion
    my $line_map = $view->line_map();
    my $has_expanded = $line_map && $line_map->has_expanded_hunks();

    # Build visible entries from LineMap or simple doc-line mapping
    my @entries;
    if ($has_expanded) {
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

        # Position cursor at start of this row (row 4 is first text row, after menu, tabs, and ruler)
        $output .= _move_to($screen_row + 4, $tree_width + 1);

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
            my $char_hl = $hunk_char_diffs{$hunk_idx}{old}{$entry->{base_line}};
            $output .= $class->_render_old_line_row(
                $doc, $view, $theme, $width, $gutter_width,
                $entry, $highlighter, \$base_highlighter, $char_hl
            );
            $output .= $class->_render_minimap_column($minimap_data, $screen_row, $theme)
                if $minimap_width > 0;
            $output .= RESET;
            $output .= CLEAR_LINE;
            next;
        }

        my $doc_line = $entry ? $entry->{line} : ($scroll_line + $screen_row);
        my $is_cursor_line = ($doc_line == $cursor_line);
        my $is_hunk_line = $entry && defined $entry->{hunk_idx};

        # Line number gutter with VCS indicator (single column)
        if ($doc_line < $doc->line_count()) {
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

            # Apply horizontal scroll (now in visual columns)
            if ($scroll_col > 0 && $scroll_col < length($expanded_content)) {
                $expanded_content = substr($expanded_content, $scroll_col);
            }
            elsif ($scroll_col >= length($expanded_content)) {
                $expanded_content = '';
            }

            # Truncate to width (display columns, not character count)
            my $content_display_width = _display_width($expanded_content);
            if ($content_display_width > $width) {
                ($expanded_content, $content_display_width) = _truncate_to_display_width($expanded_content, $width);
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

            # Render with selection, syntax, match, and cursor highlighting
            $output .= $class->_render_line_with_highlights(
                $expanded_content, $doc_line, $scroll_col, $width,
                $view, $theme, $cursor_line, $visual_cursor_col, $is_cursor_line, \@visual_tokens,
                $full_line_content, \@visual_matches,
                $is_hunk_line ? 'new' : undef, $new_char_hl,
                \@visual_capture_regions
            );

            # Fill remaining space with appropriate background
            my $fill_bg = $is_cursor_line ? $line_bg
                        : $is_hunk_line   ? $line_bg
                        :                   $theme->color('bg');
            $output .= $fill_bg . (' ' x ($width - $content_display_width)) if $content_display_width < $width;
        }
        else {
            # Empty line (beyond document)
            my $empty_bg = $theme->color('empty_line_bg');
            $output .= $empty_bg . (' ' x $width);
        }

        # Render minimap column for this row
        $output .= $class->_render_minimap_column($minimap_data, $screen_row, $theme)
            if $minimap_width > 0;

        $output .= RESET;
        $output .= CLEAR_LINE;
    }

    return $output;
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

    my $output = '';
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

    # Render sticky headers at top
    for my $sticky (@$stickies) {
        last if $row_idx >= $height;
        my $screen_row = $row_idx + 2;  # tree starts at row 2

        $output .= _move_to($screen_row, 1);
        $output .= $class->_render_tree_node_content(
            $sticky, $content_width, $theme, 0, 1, $focused,
            $has_scrollbar, $row_idx, $sb, undef, []
        );
        # Border
        $output .= $border_fg . $tree_bg . $border_char;
        $row_idx++;
    }

    # Render filter input row if active
    if ($filter_active && $row_idx < $height) {
        my $screen_row = $row_idx + 2;
        $output .= _move_to($screen_row, 1);
        $output .= $theme->color('tree_filter_bg') . $theme->color('tree_filter_fg');
        my $query = $tree->filter_query() // '';
        my $prefix = ' / ';
        my $display = $prefix . $query;
        if (length($display) > $content_width) {
            $display = substr($display, 0, $content_width);
        }
        $output .= $display;
        my $pad = $content_width - length($display);
        $output .= ' ' x $pad if $pad > 0;

        # Scrollbar column
        if ($has_scrollbar) {
            $output .= $tree_bg . ' ';
        }

        # Border
        $output .= $border_fg . $tree_bg . $border_char;
        $row_idx++;
    }

    # Render tree content rows
    my $sticky_count = $row_idx;  # rows consumed by stickies + filter
    my $available = $height - $sticky_count;

    for my $i (0 .. $available - 1) {
        last if $row_idx >= $height;
        my $flat_idx = $scroll + $i;
        my $screen_row = $row_idx + 2;

        $output .= _move_to($screen_row, 1);

        if ($flat_idx <= $#$flat) {
            my $node = $flat->[$flat_idx];
            my $d = $node->{depth};
            my $is_cursor = ($focused && $flat_idx == $cursor);
            my $node_is_last = $is_last[$flat_idx];

            # Snapshot the current guide state for this node's ancestors
            my @guides_for_node;
            for my $l (0 .. $d - 1) {
                push @guides_for_node, ($guide_active[$l] ? 1 : 0);
            }

            $output .= $class->_render_tree_node_content(
                $node, $content_width, $theme, $is_cursor, 0, $focused,
                $has_scrollbar, $row_idx, $sb, $node_is_last, \@guides_for_node
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
        $row_idx++;
    }

    return $output;
}

sub _render_tree_node_content {
    my ($class, $node, $width, $theme, $is_cursor, $is_sticky, $focused,
        $has_scrollbar, $row_idx, $sb, $is_last, $guides) = @_;

    my $output = '';

    # Choose background/foreground
    my ($bg, $fg);
    if ($is_sticky) {
        $bg = $theme->color('tree_sticky_bg');
        $fg = $theme->color('tree_sticky_fg');
    } elsif ($is_cursor) {
        $bg = $theme->color('tree_cursor_bg');
        $fg = $theme->color('tree_cursor_fg');
    } else {
        $bg = $focused ? $theme->color('tree_focused_bg') : $theme->color('tree_bg');
        $fg = $theme->color('tree_fg');
    }

    $output .= $bg;

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
    my $vcs_char = Zepto::Chars->get('vcs_expanded');  # Fat block for expanded lines
    $output .= $gutter_bg . $vcs_color . $vcs_char;
    # Blank padding for the rest of the gutter
    $output .= $gutter_bg . ' ' x ($gutter_width - 1);

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

    # Apply horizontal scroll
    my $scroll_col = $view->scroll_col();
    if ($scroll_col > 0 && $scroll_col < length($expanded_content)) {
        $expanded_content = substr($expanded_content, $scroll_col);
    } elsif ($scroll_col >= length($expanded_content)) {
        $expanded_content = '';
    }

    # Truncate to width (display columns, not character count)
    my $old_content_display_width = _display_width($expanded_content);
    if ($old_content_display_width > $width) {
        ($expanded_content, $old_content_display_width) = _truncate_to_display_width($expanded_content, $width);
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
    for my $i (0 .. $len - 1) {
        my $char = substr($expanded_content, $i, 1);
        my $char_fg = $syntax_fg[$i] // $fg;
        my $bg = ($i >= $vis_hl_start && $i < $vis_hl_end) ? $hl_bg : $line_bg;
        if ($bg ne $last_bg) {
            $output .= $bg . $char_fg . $char;
            $last_bg = $bg;
        } else {
            $output .= $char_fg . $char;
        }
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
    my ($class, $content, $line_num, $scroll_col, $width, $view, $theme, $cursor_line, $cursor_col, $is_cursor_line, $tokens, $orig_content, $matches, $diff_mode, $char_highlight, $capture_regions) = @_;

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
    my ($sel_start_line, $sel_start_col, $sel_end_line, $sel_end_col);
    my ($sel_start, $sel_end) = (-1, -1);

    if ($has_selection) {
        ($sel_start_line, $sel_start_col, $sel_end_line, $sel_end_col) = $view->selection();
        my $line_in_selection = ($line_num >= $sel_start_line && $line_num <= $sel_end_line);

        if ($line_in_selection) {
            $sel_start = 0;
            $sel_end = $len;

            if ($line_num == $sel_start_line) {
                # Convert character position to visual column
                my $visual_sel_start = _char_to_visual_col($orig_content, $sel_start_col);
                $sel_start = $visual_sel_start - $scroll_col;
                $sel_start = 0 if $sel_start < 0;
            }

            if ($line_num == $sel_end_line) {
                # Convert character position to visual column
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
        # Check if in selection
        elsif ($sel_start >= 0 && $i >= $sel_start && $i < $sel_end) {
            $char_bg = $theme->color('selection_bg');
            $char_fg = $syntax_fg[$i] // $fg;  # Preserve syntax highlighting
            $style_key = "sel:" . ($syntax_fg[$i] // 'def');
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
        if ($style_key ne $last_style) {
            $output .= $char_bg . $char_fg;
            $last_style = $style_key;
        }

        $output .= $char;
    }

    return $output;
}

# Render the status bar with Powerline segments
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
        $output .= RESET . CLEAR_LINE;
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

    # Calculate middle fill (arrow char only in powerline mode)
    my $segment_overhead = Zepto::Chars->enabled() ? 1 : 0;
    my $middle = $cols - $file_width - $segment_overhead - $hint_width;
    $middle = 0 if $middle < 0;

    # Render: [file segment][arrow][middle fill][hint]
    # File segment
    $output .= $theme->color('status_file_bg') . $theme->color('status_file_fg');
    $output .= " $display_path";
    if ($is_dirty) {
        $output .= $theme->color('status_modified_fg');
        $output .= " " . Zepto::Chars->get('modified');
        $output .= $theme->color('status_file_fg');
    }
    $output .= ' ';

    # Arrow transition: file -> middle (only in powerline mode)
    if (Zepto::Chars->enabled()) {
        $output .= $theme->color('status_bg') . $theme->color('status_file_edge');
        $output .= $ar;
    }

    # Middle fill
    $output .= $theme->color('status_bg') . $theme->color('status_fg');
    $output .= ' ' x $middle if $middle > 0;

    # Hint (right-aligned, colored by hunk type)
    if ($hint_width > 0) {
        $output .= $theme->color('status_bg');
        $output .= $hint_color // $theme->color('gutter_fg');
        $output .= $hint_text;
    }

    $output .= RESET;
    $output .= CLEAR_LINE;

    return $output;
}

# Store and retrieve status button positions for click handling
{
    my $_status_buttons = [];
    sub _set_status_buttons { shift; $_status_buttons = shift; }
    sub get_status_buttons { return @{$_status_buttons}; }
}

# Render dropdown menu
sub _render_dropdown {
    my ($class, $theme, $ui, $total_cols, $prefs) = @_;

    my $output = '';

    my $menu_key = $ui->{menu_open};
    my $selected = $ui->{menu_selected} // 0;

    # Use shared menu definitions
    my $items = $MENU_ITEMS{$menu_key} // [];
    return $output unless @$items;

    # Calculate menu position and size (dynamically from menu definitions)
    my $positions = get_menu_positions();
    my $menu_x = $positions->{$menu_key}{x} // 1;

    my $menu_width = MENU_DROPDOWN_WIDTH;
    my $menu_height = scalar @$items + 2;  # +2 for top/bottom borders

    # Get box drawing characters
    my $box_tl = Zepto::Chars->get('box_tl');
    my $box_tr = Zepto::Chars->get('box_tr');
    my $box_bl = Zepto::Chars->get('box_bl');
    my $box_br = Zepto::Chars->get('box_br');
    my $box_h = Zepto::Chars->get('box_h');
    my $box_v = Zepto::Chars->get('box_v');
    my $arrow_r = Zepto::Chars->get('arrow_right');

    # Top border (row 2, overlays tab bar — directly below menu bar)
    $output .= _move_to(2, $menu_x);
    $output .= $theme->color('dropdown_bg') . $theme->color('dropdown_border');
    $output .= $box_tl . ($box_h x ($menu_width - 2)) . $box_tr;

    # Menu items
    for my $i (0 .. scalar(@$items) - 1) {
        my $item = $items->[$i];
        my $row = 3 + $i;  # Start below top border (row 2)

        $output .= _move_to($row, $menu_x);
        $output .= $theme->color('dropdown_bg') . $theme->color('dropdown_border');
        $output .= $box_v;

        if ($item->{separator}) {
            $output .= $theme->color('dropdown_bg');
            $output .= $theme->color('dropdown_border');
            $output .= $box_h x ($menu_width - 2);
        }
        else {
            my $is_selected = ($i == $selected);

            if ($is_selected) {
                $output .= $theme->color('dropdown_selected_bg');
                $output .= $theme->color('dropdown_selected_fg');
            }
            else {
                $output .= $theme->color('dropdown_bg');
                $output .= $theme->color('dropdown_fg');
            }

            # Selection indicator: arrow when selected, spaces otherwise
            my $prefix = $is_selected ? ($arrow_r . ' ') : '  ';
            $output .= $prefix;

            my $label = $item->{label} // '';
            my $shortcut = $item->{shortcut} // '';

            # Fixed prefix width of 2 (arrow or spaces)
            my $label_space = $menu_width - 3 - 2 - length($shortcut);
            if (length($label) > $label_space) {
                $label = substr($label, 0, $label_space);
            }

            $output .= $label;
            $output .= ' ' x ($label_space - length($label));

            if ($shortcut && !$is_selected) {
                $output .= $theme->color('dropdown_shortcut');
            }
            $output .= $shortcut;
            $output .= ' ';
        }

        $output .= $theme->color('dropdown_bg') . $theme->color('dropdown_border');
        $output .= $box_v;
        $output .= RESET;
    }

    # Bottom border
    $output .= _move_to(3 + scalar(@$items), $menu_x);
    $output .= $theme->color('dropdown_bg') . $theme->color('dropdown_border');
    $output .= $box_bl . ($box_h x ($menu_width - 2)) . $box_br;
    $output .= RESET;

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

    # Get box drawing characters (rounded when powerline enabled)
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

    # Position cursor in input field
    my $cursor_x = $x + 2 + $cursor_pos;
    if ($cursor_x > $x + $dialog_width - 4) {
        $cursor_x = $x + $dialog_width - 4;
    }
    $output .= _move_to($y + 3, $cursor_x);

    return $output;
}

# Calculate screen position for cursor
sub _cursor_screen_pos {
    my ($class, $view, $gutter_width, $menu_height, $doc, $tree_width) = @_;
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

    # Account for expanded hunk rows via LineMap
    my $lm = $view->line_map();
    my $screen_row;
    if ($lm && $lm->has_expanded_hunks()) {
        my $cursor_display = $lm->doc_line_to_display($cursor_line);
        my $scroll_display = $lm->scroll_display_start($scroll_line);
        $screen_row = $cursor_display - $scroll_display + $menu_height + 3;
    } else {
        # +3 for menu bar, tab bar, and ruler bar
        $screen_row = $cursor_line - $scroll_line + $menu_height + 3;
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
    my $value = $input->{value} // '';
    my $hint = $input->{hint} // '';

    # Render: " Prompt: [input value          ] (hint) "
    my $prompt_str = ' ' . $prompt . ' ';
    $output .= $prompt_str;

    # Input field with distinct background
    $output .= $theme->color('dialog_input_bg');
    $output .= $theme->color('dialog_input_fg');

    # Calculate width for input field (fixed width, not stretched)
    my $prompt_len = length($prompt_str);
    my $hint_str = $hint ? " ($hint)" : '';
    my $hint_len = length($hint_str);
    my $input_width = 12;  # Fixed narrow width for input

    # Display value (truncate from left if too long)
    my $display_value = $value;
    if (length($display_value) > $input_width) {
        $display_value = substr($display_value, length($display_value) - $input_width);
    }
    $output .= $display_value;

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

    $output .= RESET;
    $output .= CLEAR_LINE;

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

    # Powerline rounded pill characters
    my $rl = Zepto::Chars->get('powerline_round_left');
    my $rr = Zepto::Chars->get('powerline_round_right');

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
    my $display_value = $value;
    if (length($display_value) > $input_width) {
        $display_value = substr($display_value, length($display_value) - $input_width);
    }
    if ($regex_on && $capture_count > 0) {
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
    my $replace_display = $replace_value;
    if (length($replace_display) > $input_width) {
        $replace_display = substr($replace_display, length($replace_display) - $input_width);
    }
    if ($regex_on && $capture_count > 0) {
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
        $content .= $theme->color('status_dim') . '^R';
        $content .= $theme->color('menu_active_text') . ' ';
        $content .= $theme->color('status_bg') . $theme->color('menu_active_edge');
        $content .= $rr;
    } else {
        $content .= $theme->color('status_bg') . $theme->color('menu_pill_edge');
        $content .= $rl;
        $content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
        $content .= ' .* ';
        $content .= $theme->color('status_dim') . '^R';
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
        $content .= $theme->color('status_dim') . '^C';
        $content .= $theme->color('menu_active_text') . ' ';
        $content .= $theme->color('status_bg') . $theme->color('menu_active_edge');
        $content .= $rr;
    } else {
        $content .= $theme->color('status_bg') . $theme->color('menu_pill_edge');
        $content .= $rl;
        $content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
        $content .= ' Aa ';
        $content .= $theme->color('status_dim') . '^C';
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
    $output .= RESET;
    $output .= CLEAR_LINE;

    return $output;
}

sub _render_prompt {
    my ($class, $theme, $prompt, $cols, $rows) = @_;

    my $output = '';
    $output .= $theme->color('status_bg') . $theme->color('status_fg');

    my $text = $prompt->{text} // '';
    my @options = @{$prompt->{options} // []};

    # Build prompt string: "Unsaved changes. [S]ave [D]iscard [C]ancel"
    my $prompt_str = ' ' . $text . ' ';

    # Track button positions for click handling
    my @buttons;
    my $x_pos = length($prompt_str) + 1;  # +1 for 1-indexed columns

    for my $opt (@options) {
        my $key = uc($opt->{key});
        my $label = $opt->{label};

        # Format: [K]eyLabel with K highlighted
        my $btn_start = length($prompt_str);
        $prompt_str .= ' [';
        $prompt_str .= $key;
        $prompt_str .= ']';
        $prompt_str .= substr($label, 1) if length($label) > 1;  # Rest of label after first char
        $prompt_str .= ' ';
        my $btn_end = length($prompt_str);

        push @buttons, {
            key => lc($opt->{key}),
            x_start => $btn_start + 1,
            x_end => $btn_end,
            y => $rows,
        };
    }

    # Render with highlighted keys
    my $rendered = ' ' . $text . ' ';
    for my $opt (@options) {
        my $key = uc($opt->{key});
        my $label = $opt->{label};
        my $rest = length($label) > 1 ? substr($label, 1) : '';

        $rendered .= ' [';
        $output .= $rendered;
        $rendered = '';

        # Highlighted key
        $output .= $theme->color('menu_hotkey');
        $output .= $key;
        $output .= $theme->color('status_fg');

        $rendered = ']' . $rest . ' ';
    }
    $output .= $rendered;

    # Pad to fill status bar
    my $display_len = length($prompt_str);
    my $padding = $cols - $display_len;
    $output .= ' ' x $padding if $padding > 0;

    $output .= RESET;
    $output .= CLEAR_LINE;

    $class->_set_prompt_buttons(\@buttons);

    return $output;
}

# =============================================================================
# File Picker Rendering
# =============================================================================

sub _render_file_picker {
    my ($class, $theme, $picker, $text_height, $cols) = @_;

    my $output = '';

    my $query = $picker->query() // '';
    my @filtered = @{$picker->filtered() // []};
    my $selected = $picker->selected() // 0;
    my $scroll = $picker->scroll() // 0;
    my $total = $picker->total_files();
    my $filtered_count = $picker->filtered_count();

    # Row 4: Search input (after menu, tabs, and ruler)
    $output .= _move_to(4, 1);
    $output .= $theme->color('dialog_bg');
    $output .= $theme->color('dialog_fg');
    $output .= ' > ';
    $output .= $theme->color('dialog_input_fg');
    $output .= $query;

    # Fill rest of search row
    my $search_fill = $cols - 3 - length($query);
    $output .= ' ' x $search_fill if $search_fill > 0;
    $output .= RESET;
    $output .= CLEAR_LINE;

    # Separator line
    $output .= _move_to(5, 1);
    $output .= $theme->color('dialog_border');
    $output .= Zepto::Chars->get('box_h') x $cols;
    $output .= RESET;

    # File list (rows 6+ to text_height)
    my $list_height = $text_height - 2;  # -2 for search row and separator
    $list_height = 1 if $list_height < 1;

    for my $i (0 .. $list_height - 1) {
        my $row = 6 + $i;
        my $file_idx = $scroll + $i;

        $output .= _move_to($row, 1);

        if ($file_idx < @filtered) {
            my $file = $filtered[$file_idx];
            my $is_selected = ($file_idx == $selected);

            if ($is_selected) {
                $output .= $theme->color('dropdown_selected_bg');
                $output .= $theme->color('dropdown_selected_fg');
                $output .= ' > ';
            } else {
                $output .= $theme->color('bg');
                $output .= $theme->color('fg');
                $output .= '   ';
            }

            # Truncate filename if needed
            my $max_len = $cols - 4;
            my $display = $file;
            if (length($display) > $max_len) {
                $display = '...' . substr($display, length($display) - $max_len + 3);
            }
            $output .= $display;

            # Fill rest of line
            my $fill = $cols - 3 - length($display);
            $output .= ' ' x $fill if $fill > 0;
        } else {
            # Empty row (beyond file list)
            $output .= $theme->color('empty_line_bg');
            $output .= ' ' x $cols;
        }

        $output .= RESET;
        $output .= CLEAR_LINE;
    }

    return $output;
}

1;
