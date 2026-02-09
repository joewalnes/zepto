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
        { label => 'Find',          shortcut => 'Ctrl+F', action => 'find' },
        { label => 'Find Next',     shortcut => 'Ctrl+J', action => 'find_next' },
        { label => 'Find Previous', shortcut => 'Ctrl+K', action => 'find_prev' },
        { separator => 1 },
        { label => 'Replace',       shortcut => 'Ctrl+R', action => 'replace' },
        { separator => 1 },
        { label => 'Go to Line',    shortcut => 'Ctrl+G', action => 'goto' },
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
sub get_gutter_width {
    my ($class, $line_count) = @_;
    $line_count //= 1;  # Default if undef
    my $gutter_width = length("$line_count") + 1;  # +1 for padding
    $gutter_width = MIN_GUTTER_WIDTH if $gutter_width < MIN_GUTTER_WIDTH;        # Minimum width
    return $gutter_width;
}

# Render the complete editor screen
# Returns a string of escape sequences
sub render {
    my ($class, %args) = @_;

    my $doc      = $args{document};
    my $view     = $args{view};
    my $ui       = $args{ui} // {};
    my $theme    = $args{theme};
    my $prefs    = $args{prefs};
    my $rows     = $args{rows} // DEFAULT_ROWS;
    my $cols     = $args{cols} // DEFAULT_COLS;
    my $message  = $args{message} // '';

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
    my $status_height = 1;
    my $text_height = $rows - $menu_height - $status_height;
    $text_height = 1 if $text_height < 1;

    # Calculate gutter width based on line count
    my $line_count = $doc ? $doc->line_count() : 1;
    my $gutter_width = $class->get_gutter_width($line_count);

    my $text_width = $cols - $gutter_width;
    $text_width = MIN_TEXT_WIDTH if $text_width < MIN_TEXT_WIDTH;

    # Render menu bar (row 1)
    $output .= _move_to(1, 1);
    $output .= $class->_render_menu_bar($theme, $cols, $ui);

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
            $text_height, $text_width, $gutter_width
        );
    }

    # Render status bar (last row) - prompt/footer_input replace normal content
    $output .= _move_to($rows, 1);
    if ($ui->{prompt}) {
        $output .= $class->_render_prompt(
            $theme, $ui->{prompt}, $cols, $rows
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
        $output .= _move_to(2, 4 + $query_len);  # Row 2, after "> "
        $output .= SHOW_CURSOR;
    } elsif ($ui->{footer_input}) {
        # Position cursor in footer input field
        my $input = $ui->{footer_input};
        my $prompt_len = length($input->{prompt} // '') + 2;  # +2 for leading/trailing space
        my $cursor_pos = $input->{cursor} // 0;
        $output .= _move_to($rows, $prompt_len + $cursor_pos + 1);
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
            $view, $gutter_width, $menu_height
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

# Render the text area with line numbers
sub _render_text_area {
    my ($class, $doc, $view, $theme, $height, $width, $gutter_width) = @_;

    my $output = '';

    return $output unless $doc && $view;

    my $scroll_line = $view->scroll_line();
    my $scroll_col = $view->scroll_col();
    my $cursor_line = $view->cursor_line();
    my $cursor_col = $view->cursor_col();

    for my $screen_row (0 .. $height - 1) {
        my $doc_line = $scroll_line + $screen_row;
        my $is_cursor_line = ($doc_line == $cursor_line);

        # Position cursor at start of this row (row 2 is first text row, after menu)
        $output .= _move_to($screen_row + 2, 1);

        # Line number gutter (highlight if cursor line)
        if ($is_cursor_line) {
            $output .= $theme->color('cursor_line_bg') . $theme->color('gutter_fg');
        } else {
            $output .= $theme->color('gutter_bg') . $theme->color('gutter_fg');
        }

        if ($doc_line < $doc->line_count()) {
            my $line_num = sprintf("%*d", $gutter_width - 1, $doc_line + 1);
            $output .= $line_num . ' ';
        }
        else {
            $output .= ' ' x $gutter_width;
        }

        # Background (highlight if cursor line)
        my $line_bg = $is_cursor_line ? $theme->color('cursor_line_bg') : $theme->color('bg');
        $output .= $line_bg . $theme->color('fg');

        # Text content
        if ($doc_line < $doc->line_count()) {
            my $line_content = $doc->get_line_content($doc_line);

            # Apply horizontal scroll
            if ($scroll_col > 0 && $scroll_col < length($line_content)) {
                $line_content = substr($line_content, $scroll_col);
            }
            elsif ($scroll_col >= length($line_content)) {
                $line_content = '';
            }

            # Truncate to width
            if (length($line_content) > $width) {
                $line_content = substr($line_content, 0, $width);
            }

            # Render with selection and cursor highlighting
            $output .= $class->_render_line_with_highlights(
                $line_content, $doc_line, $scroll_col, $width,
                $view, $theme, $cursor_line, $cursor_col, $is_cursor_line
            );

            # Fill remaining space with cursor line background if needed
            my $fill = $width - length($line_content);
            if ($fill > 0) {
                $output .= $line_bg . ' ' x $fill;
            }
        }
        else {
            # Empty line (beyond document) - use distinct background
            $output .= $theme->color('empty_line_bg');
            $output .= ' ' x $width;
        }

        $output .= RESET;
        $output .= CLEAR_LINE;
    }

    return $output;
}

# Render a line with selection highlighting
sub _render_line_with_highlights {
    my ($class, $content, $line_num, $scroll_col, $width, $view, $theme, $cursor_line, $cursor_col, $is_cursor_line) = @_;

    my $output = '';
    my $len = length($content);

    # Determine background color (cursor line highlight or normal)
    my $line_bg = $is_cursor_line ? $theme->color('cursor_line_bg') : $theme->color('bg');

    # Get selection info
    my $has_selection = $view->has_selection();
    return $content unless $has_selection;

    my ($sel_start_line, $sel_start_col, $sel_end_line, $sel_end_col) = $view->selection();

    # Check if this line has any selection
    my $line_in_selection = ($line_num >= $sel_start_line && $line_num <= $sel_end_line);
    return $content unless $line_in_selection;

    # Calculate selection range on this line
    my $sel_start = 0;
    my $sel_end = $len;

    if ($line_num == $sel_start_line) {
        $sel_start = $sel_start_col - $scroll_col;
        $sel_start = 0 if $sel_start < 0;
    }

    if ($line_num == $sel_end_line) {
        $sel_end = $sel_end_col - $scroll_col;
        $sel_end = 0 if $sel_end < 0;
    }

    # Render in three parts: before, selected, after
    if ($sel_start > 0) {
        $output .= substr($content, 0, $sel_start);
    }

    if ($sel_end > $sel_start && $sel_start < $len) {
        $output .= $theme->color('selection_bg') . $theme->color('selection_fg');
        my $end = $sel_end > $len ? $len : $sel_end;
        $output .= substr($content, $sel_start, $end - $sel_start);
        $output .= $line_bg . $theme->color('fg');
    }

    if ($sel_end < $len) {
        $output .= substr($content, $sel_end);
    }

    return $output;
}

# Render the status bar with Powerline segments
sub _render_status_bar {
    my ($class, $doc, $view, $theme, $cols, $message) = @_;

    my $output = '';
    my $ar = Zepto::Chars->get('arrow_right');
    my $al = Zepto::Chars->get('arrow_left');

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

    # Get position info
    my $line = $view ? $view->cursor_line() + 1 : 1;
    my $col = $view ? $view->cursor_col() + 1 : 1;
    my $col_padded = sprintf("%-3d", $col);  # Left-align, pad to 3 digits to prevent jiggle
    my $pos_text = " $line:$col_padded";

    # Build left segment: filename with optional modified indicator
    my $file_text = " $filename$modified_icon ";
    my $file_width = length($filename) + 2;
    $file_width += 2 if $is_dirty;  # For modified icon + space

    # Build right segment: position (col is always 3 chars wide)
    # Format: " line:col" = space(1) + line + colon(1) + col(3)
    my $pos_width = 1 + length("$line") + 1 + 3;

    # Calculate middle fill (arrow chars only in powerline mode)
    my $segment_overhead = Zepto::Chars->enabled() ? 2 : 0;
    my $middle = $cols - $file_width - $pos_width - $segment_overhead;
    $middle = 0 if $middle < 0;

    # Render: [file segment][arrow][middle fill][arrow][pos segment]
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

    # Arrow transition: middle -> pos (only in powerline mode)
    if (Zepto::Chars->enabled()) {
        # For left arrow: bg=where we came from, fg=where we're going
        $output .= $theme->color('status_bg') . $theme->color('status_pos_edge');
        $output .= $al;
    }

    # Position segment
    $output .= $theme->color('status_pos_bg') . $theme->color('status_pos_fg');
    $output .= $pos_text;

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

    # Top border
    $output .= _move_to(2, $menu_x);
    $output .= $theme->color('dropdown_bg') . $theme->color('dropdown_border');
    $output .= $box_tl . ($box_h x ($menu_width - 2)) . $box_tr;

    # Menu items
    for my $i (0 .. scalar(@$items) - 1) {
        my $item = $items->[$i];
        my $row = 3 + $i;  # Start below top border

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
    my ($class, $view, $gutter_width, $menu_height) = @_;

    my $cursor_line = $view->cursor_line();
    my $cursor_col = $view->cursor_col();
    my $scroll_line = $view->scroll_line();
    my $scroll_col = $view->scroll_col();

    my $screen_row = $cursor_line - $scroll_line + $menu_height + 1;
    my $screen_col = $cursor_col - $scroll_col + $gutter_width + 1;  # +1 for 1-indexed

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

    # Render: " Prompt: [input value          ] "
    my $prompt_str = ' ' . $prompt . ' ';
    $output .= $prompt_str;

    # Input field with distinct background
    $output .= $theme->color('dialog_input_bg');
    $output .= $theme->color('dialog_input_fg');

    # Calculate available width for input field
    my $prompt_len = length($prompt_str);
    my $input_width = $cols - $prompt_len - 2;  # -2 for padding
    $input_width = 10 if $input_width < 10;

    # Display value (truncate from left if too long)
    my $display_value = $value;
    if (length($display_value) > $input_width) {
        $display_value = substr($display_value, length($display_value) - $input_width);
    }
    $output .= $display_value;

    # Fill remaining input area
    my $fill = $input_width - length($display_value);
    $output .= ' ' x $fill if $fill > 0;

    # Pad rest of status bar
    $output .= $theme->color('status_bg') . $theme->color('status_fg');
    my $remaining = $cols - $prompt_len - $input_width;
    $output .= ' ' x $remaining if $remaining > 0;

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

    # Row 2: Search input
    $output .= _move_to(2, 1);
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
    $output .= _move_to(3, 1);
    $output .= $theme->color('dialog_border');
    $output .= Zepto::Chars->get('box_h') x $cols;
    $output .= RESET;

    # File list (rows 4 to text_height)
    my $list_height = $text_height - 2;  # -2 for search row and separator
    $list_height = 1 if $list_height < 1;

    for my $i (0 .. $list_height - 1) {
        my $row = 4 + $i;
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
