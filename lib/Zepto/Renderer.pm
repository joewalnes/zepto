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
        { label => 'Save & Quit', shortcut => 'Ctrl+W', action => 'save_quit' },
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
            $visual_col++;
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

# Move cursor to row, col (1-indexed)
sub _move_to {
    my ($row, $col) = @_;
    return CSI . $row . ';' . $col . 'H';
}

# Calculate gutter width based on line count
# Exported so Editor.pm can use same calculation for mouse position mapping
# Gutter must fit: VCS indicators (2 cols) + cursor line badge (round_left + digits + space + arrow_right)
# Layout: [vcs_del][vcs_chg][pad][round_left][digits][space][arrow_right] = 2 + digits + 3
# and normal lines: [vcs_del][vcs_chg][space][right-aligned digits][space]
sub get_gutter_width {
    my ($class, $line_count) = @_;
    $line_count //= 1;  # Default if undef
    my $max_digits = length("$line_count");
    my $gutter_width = $max_digits + 5;  # +5 for VCS (2) + badge chars (round_left + space + arrow_right = 3)
    $gutter_width = MIN_GUTTER_WIDTH + 2 if $gutter_width < MIN_GUTTER_WIDTH + 2;
    return $gutter_width;
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
    my $ruler_height = 1;
    my $status_height = 1;
    my $text_height = $rows - $menu_height - $ruler_height - $status_height;
    $text_height = 1 if $text_height < 1;

    # Calculate gutter width based on line count
    my $line_count = $doc ? $doc->line_count() : 1;
    my $gutter_width = $class->get_gutter_width($line_count);

    my $text_width = $cols - $gutter_width;
    $text_width = MIN_TEXT_WIDTH if $text_width < MIN_TEXT_WIDTH;

    # Render menu bar (row 1)
    $output .= _move_to(1, 1);
    $output .= $class->_render_menu_bar($theme, $cols, $ui);

    # Render ruler bar (row 2)
    $output .= _move_to(2, 1);
    $output .= $class->_render_ruler_bar($theme, $cols, $gutter_width, $view, $doc);

    # Render text area or file picker
    if ($ui->{file_picker}) {
        # File picker replaces the text area
        $output .= $class->_render_file_picker(
            $theme, $ui->{file_picker}, $text_height, $cols
        );
    } else {
        # Normal text area with line numbers (rows 2 to 2+text_height-1)
        $output .= $class->_render_text_area(
            $doc, $view, $theme,
            $text_height, $text_width, $gutter_width, $highlighter,
            $ui->{find_mode}
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
        $output .= $class->_render_status_bar(
            $doc, $view, $theme, $cols, $message
        );
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
        $output .= _move_to(3, 4 + $query_len);  # Row 3, after "> "
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
        my $match_text = $match_count == 0
            ? (length($value) ? 'No matches' : '')
            : (($current + 1) . ' of ' . $match_count);
        my $right_side_width = 45 + length($match_text);
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
    } elsif ($view && $doc) {
        # Position terminal cursor for editing
        my ($cursor_row, $cursor_col) = $class->_cursor_screen_pos(
            $view, $gutter_width, $menu_height, $doc
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

# Render the ruler bar showing column positions
sub _render_ruler_bar {
    my ($class, $theme, $cols, $gutter_width, $view, $doc) = @_;

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

    # Calculate ruler width (text area width)
    my $ruler_width = $cols - $gutter_width;

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
    my ($class, $doc, $view, $theme, $height, $width, $gutter_width, $highlighter, $find_mode) = @_;

    my $output = '';

    return $output unless $doc && $view;

    my $scroll_line = $view->scroll_line();
    my $visible_start = $scroll_line;
    my $visible_end = $scroll_line + $height;

    # Precompute match ranges by line if in find mode (only visible lines)
    # Use viewport_matches for O(viewport) instead of O(all_matches)
    my %line_matches;  # line_num => [{start, end, is_current}, ...]
    if ($find_mode && $find_mode->{matches} && @{$find_mode->{matches}}) {
        my $matches = $find_mode->{matches};
        my $current = $find_mode->{current} // 0;

        # Find current match line for highlighting
        my $current_line = $matches->[$current]{line} if $current < @$matches;
        my $current_col = $matches->[$current]{col} if $current < @$matches;

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

    # Calculate the visual cursor column ONCE from the cursor line's content
    # This ensures the crosshair is a straight vertical line regardless of tabs on other lines
    my $cursor_line_content = $cursor_line < $doc->line_count()
        ? $doc->get_line_content($cursor_line)
        : '';
    my $visual_cursor_col = _char_to_visual_col($cursor_line_content, $cursor_col);
    my $visible_cursor_col = $visual_cursor_col - $scroll_col;

    for my $screen_row (0 .. $height - 1) {
        my $doc_line = $scroll_line + $screen_row;
        my $is_cursor_line = ($doc_line == $cursor_line);

        # Position cursor at start of this row (row 3 is first text row, after menu and ruler)
        $output .= _move_to($screen_row + 3, 1);

        # Line number gutter with VCS indicators (2 columns)
        if ($doc_line < $doc->line_count()) {
            my $line_num_str = sprintf("%d", $doc_line + 1);

            # Get VCS indicators for this line (two columns)
            # Column 1: deletion indicator (▗ or ▝)
            # Column 2: change indicator (▐ for added/modified)
            my $del_status = $doc->vcs_deletion_status($doc_line);
            my $chg_status = $doc->vcs_change_status($doc_line);

            my ($del_char, $del_color, $chg_char, $chg_color);

            # Deletion indicator (column 1)
            if ($del_status) {
                if ($del_status eq 'below') {
                    $del_char = Zepto::Chars->get('vcs_del_lower');
                } elsif ($del_status eq 'above') {
                    $del_char = Zepto::Chars->get('vcs_del_upper');
                }
                $del_color = $theme->color('vcs_deleted');
            }
            $del_char //= ' ';
            $del_color //= $theme->color('gutter_fg');

            # Change indicator (column 2)
            if ($chg_status) {
                if ($chg_status eq 'added') {
                    $chg_char = Zepto::Chars->get('vcs_added');
                    $chg_color = $theme->color('vcs_added');
                } elsif ($chg_status eq 'modified') {
                    $chg_char = Zepto::Chars->get('vcs_modified');
                    $chg_color = $theme->color('vcs_modified');
                }
            }
            $chg_char //= ' ';
            $chg_color //= $theme->color('gutter_fg');

            if ($is_cursor_line) {
                # Cursor line: [vcs_del][vcs_chg][pad][rl][digits][space][ar]
                my $rl = Zepto::Chars->get('round_left');
                my $ar = Zepto::Chars->get('arrow_right');

                # VCS indicators first (on gutter background)
                $output .= $theme->color('gutter_bg') . $del_color . $del_char;
                $output .= $theme->color('gutter_bg') . $chg_color . $chg_char;

                # Calculate padding to right-align the badge
                # Badge takes: rl(1) + digits + space(1) + ar(1) = digits + 3
                # Available: gutter_width - 2 (for VCS columns)
                my $badge_width = length($line_num_str) + 3;
                my $pad = $gutter_width - 2 - $badge_width;
                $pad = 0 if $pad < 0;

                # Padding, then badge
                $output .= $theme->color('gutter_bg') . (' ' x $pad);
                $output .= $theme->color('gutter_bg') . $theme->color('ruler_cursor_edge') . $rl;
                $output .= $theme->color('ruler_cursor_bg') . $theme->color('ruler_cursor_fg') . $line_num_str . ' ';
                # Arrow right: badge color as fg, next area color as bg
                $output .= $theme->color('cursor_line_bg') . $theme->color('ruler_cursor_edge') . $ar;
            } else {
                # Normal line: [vcs_del][vcs_chg][space][right-aligned digits][space]
                # VCS indicators first
                $output .= $theme->color('gutter_bg') . $del_color . $del_char;
                $output .= $theme->color('gutter_bg') . $chg_color . $chg_char;
                # Rest of gutter
                $output .= $theme->color('gutter_bg') . $theme->color('gutter_fg');
                # Use (gutter_width - 4) for digits: total = 2(vcs) + 1(space) + digits + 1(space) = gutter_width
                my $line_num = sprintf("%*d", $gutter_width - 4, $doc_line + 1);
                $output .= ' ' . $line_num . ' ';
            }
        }
        else {
            $output .= $theme->color('gutter_bg') . $theme->color('gutter_fg');
            $output .= ' ' x $gutter_width;
        }

        # Background (highlight if cursor line)
        my $line_bg = $is_cursor_line ? $theme->color('cursor_line_bg') : $theme->color('bg');
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

            # Note: visual_cursor_col and visible_cursor_col are calculated once before the loop
            # to ensure a straight vertical crosshair regardless of tab content on different lines

            # Apply horizontal scroll (now in visual columns)
            if ($scroll_col > 0 && $scroll_col < length($expanded_content)) {
                $expanded_content = substr($expanded_content, $scroll_col);
            }
            elsif ($scroll_col >= length($expanded_content)) {
                $expanded_content = '';
            }

            # Truncate to width
            if (length($expanded_content) > $width) {
                $expanded_content = substr($expanded_content, 0, $width);
            }

            # Render with selection, syntax, match, and cursor highlighting
            $output .= $class->_render_line_with_highlights(
                $expanded_content, $doc_line, $scroll_col, $width,
                $view, $theme, $cursor_line, $visual_cursor_col, $is_cursor_line, \@visual_tokens,
                $full_line_content, \@visual_matches
            );

            # Fill remaining space with appropriate backgrounds (crosshair column highlight)
            my $fill_start = length($expanded_content);
            my $col_bg = $theme->color('cursor_col_bg');

            for (my $i = $fill_start; $i < $width; $i++) {
                if ($is_cursor_line) {
                    $output .= $line_bg . ' ';
                }
                elsif ($i == $visible_cursor_col) {
                    $output .= $col_bg . ' ';
                }
                else {
                    $output .= $theme->color('bg') . ' ';
                }
            }
        }
        else {
            # Empty line (beyond document) - highlight cursor column for crosshair
            # Uses pre-calculated visible_cursor_col for consistent vertical alignment
            my $empty_bg = $theme->color('empty_line_bg');
            my $col_bg = $theme->color('cursor_col_bg');

            for (my $i = 0; $i < $width; $i++) {
                if ($i == $visible_cursor_col) {
                    $output .= $col_bg . ' ';
                }
                else {
                    $output .= $empty_bg . ' ';
                }
            }
        }

        $output .= RESET;
        $output .= CLEAR_LINE;
    }

    return $output;
}

# Render a line with selection, syntax, match, and crosshair highlighting
# $content: tab-expanded content for this line
# $orig_content: original content (with tabs) for position conversion
# $cursor_col: visual cursor column (already converted)
# $matches: array of {start, end, is_current} for find matches on this line
sub _render_line_with_highlights {
    my ($class, $content, $line_num, $scroll_col, $width, $view, $theme, $cursor_line, $cursor_col, $is_cursor_line, $tokens, $orig_content, $matches) = @_;

    my $output = '';
    my $len = length($content);

    # Background colors
    my $bg = $theme->color('bg');
    my $line_bg = $theme->color('cursor_line_bg');
    my $col_bg = $theme->color('cursor_col_bg');
    my $fg = $theme->color('fg');
    my $match_bg = $theme->color('match_bg');
    my $match_fg = $theme->color('match_fg');
    my $current_match_bg = $theme->color('current_match_bg');
    my $current_match_fg = $theme->color('current_match_fg');

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

    # Cursor column position relative to viewport
    my $visible_cursor_col = $cursor_col - $scroll_col;

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
                $char_bg = $current_match_bg;
                $char_fg = $current_match_fg;  # Use prominent foreground for current match
                $style_key = "curmatch";
            } else {
                $char_bg = $match_bg;
                $char_fg = $match_fg;  # Muted foreground for other matches
                $style_key = "match";
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
        elsif ($i == $visible_cursor_col) {
            $char_bg = $col_bg;
            $char_fg = $syntax_fg[$i] // $fg;
            $style_key = "col:" . ($syntax_fg[$i] // 'def');
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
    my ($class, $doc, $view, $theme, $cols, $message) = @_;

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

    # Get file info
    my $filename = $doc ? $doc->filename() : '[No file]';
    my $is_dirty = $doc && $doc->is_dirty();
    my $modified_icon = $is_dirty ? ' ' . Zepto::Chars->get('modified') : '';

    # Build left segment: filename with optional modified indicator
    my $file_text = " $filename$modified_icon ";
    my $file_width = length($filename) + 2;
    $file_width += 2 if $is_dirty;  # For modified icon + space

    # Calculate middle fill (arrow char only in powerline mode)
    my $segment_overhead = Zepto::Chars->enabled() ? 1 : 0;
    my $middle = $cols - $file_width - $segment_overhead;
    $middle = 0 if $middle < 0;

    # Render: [file segment][arrow][middle fill]
    # File segment
    $output .= $theme->color('status_file_bg') . $theme->color('status_file_fg');
    $output .= " $filename";
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

    # Top border (row 2, overlays ruler bar)
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
    my ($class, $view, $gutter_width, $menu_height, $doc) = @_;

    my $cursor_line = $view->cursor_line();
    my $cursor_col = $view->cursor_col();
    my $scroll_line = $view->scroll_line();
    my $scroll_col = $view->scroll_col();

    # Convert character position to visual column (accounting for tabs)
    my $cursor_line_content = ($doc && $cursor_line < $doc->line_count())
        ? $doc->get_line_content($cursor_line)
        : '';
    my $visual_cursor_col = _char_to_visual_col($cursor_line_content, $cursor_col);

    # +2 for menu bar and ruler bar
    my $screen_row = $cursor_line - $scroll_line + $menu_height + 2;
    my $screen_col = $visual_cursor_col - $scroll_col + $gutter_width + 1;  # +1 for 1-indexed

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

    # Fixed widths for buttons/toggles on right side
    # ".* ^R" (9+1) + "Aa ^C" (9+1) + "X Esc" (9+1) + "✓ Enter" (11) + spaces
    my $right_side_width = 45 + length($match_text);

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
    if ($focus eq 'find') {
        $content .= $theme->color('dialog_input_bg') . $theme->color('dialog_input_fg');
    } else {
        $content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
    }
    my $display_value = $value;
    if (length($display_value) > $input_width) {
        $display_value = substr($display_value, length($display_value) - $input_width);
    }
    $content .= $display_value;
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
    if ($focus eq 'replace') {
        $content .= $theme->color('dialog_input_bg') . $theme->color('dialog_input_fg');
    } else {
        $content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
    }
    my $replace_display = $replace_value;
    if (length($replace_display) > $input_width) {
        $replace_display = substr($replace_display, length($replace_display) - $input_width);
    }
    $content .= $replace_display;
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

    # Add padding and match text
    my $padding_needed = $cols - $visible_width - length($match_text) - 1;
    $padding_needed = 1 if $padding_needed < 1;
    $content .= ' ' x $padding_needed;
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

    # Row 3: Search input (after menu and ruler)
    $output .= _move_to(3, 1);
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
    $output .= _move_to(4, 1);
    $output .= $theme->color('dialog_border');
    $output .= Zepto::Chars->get('box_h') x $cols;
    $output .= RESET;

    # File list (rows 5+ to text_height)
    my $list_height = $text_height - 2;  # -2 for search row and separator
    $list_height = 1 if $list_height < 1;

    for my $i (0 .. $list_height - 1) {
        my $row = 5 + $i;
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
