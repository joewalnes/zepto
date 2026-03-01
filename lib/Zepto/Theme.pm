package Zepto::Theme;
# =============================================================================
# Theme System for Zepto Editor
# =============================================================================
#
# Themes define colors for different UI elements. Each theme specifies colors
# using semantic role names, making it easy to swap themes without changing
# rendering code.
#
# Color format: ANSI escape codes or RGB values (for true-color terminals)
# =============================================================================

use strict;
use warnings;

# ANSI color codes
use constant {
    RESET   => "\x1b[0m",
    BOLD    => "\x1b[1m",
    DIM     => "\x1b[2m",
    ITALIC  => "\x1b[3m",
    UNDERLINE      => "\x1b[4m",
    STRIKETHROUGH  => "\x1b[9m",
    REVERSE        => "\x1b[7m",
};

# Create a new theme
sub new {
    my ($class, $name, $colors) = @_;
    return bless {
        name   => $name,
        colors => $colors,
    }, $class;
}

sub name { $_[0]->{name} }

# Get color escape sequence for a role
sub color {
    my ($self, $role) = @_;
    return $self->{colors}{$role} // '';
}

# Get foreground + background combined
sub style {
    my ($self, $fg_role, $bg_role) = @_;
    my $fg = $self->{colors}{$fg_role} // '';
    my $bg = $self->{colors}{$bg_role} // '';
    return $fg . $bg;
}

# Reset to default colors
sub reset {
    return RESET;
}

# =============================================================================
# Color Helpers
# =============================================================================

# Create foreground color from RGB (true-color)
sub fg_rgb {
    my ($r, $g, $b) = @_;
    return "\x1b[38;2;${r};${g};${b}m";
}

# Create background color from RGB (true-color)
sub bg_rgb {
    my ($r, $g, $b) = @_;
    return "\x1b[48;2;${r};${g};${b}m";
}

# =============================================================================
# Built-in Themes
# =============================================================================

sub dark_theme {
    my $class = shift;

    # Tokyo Night inspired - deep blues with cyan/purple accents
    return $class->new('dark', {
        # Main text area
        fg          => fg_rgb(192, 202, 245),  # Soft blue-white text
        bg          => bg_rgb(26, 27, 38),     # Deep night blue

        # Line numbers gutter
        gutter_fg   => fg_rgb(86, 95, 137),    # Muted blue-gray
        gutter_bg   => bg_rgb(22, 22, 30),     # Darker blue
        wrap_indicator_fg => fg_rgb(65, 72, 104),  # Dim gutter color for ↪ wrap indicator

        # Selection
        selection_fg => fg_rgb(192, 202, 245),
        selection_bg => bg_rgb(51, 70, 124),   # Deep blue highlight

        # Column (rectangular) selection
        column_selection_bg => bg_rgb(60, 55, 120),  # Purple-blue tint
        column_cursor_bg    => bg_rgb(80, 70, 150),  # Brighter for zero-width bars
        column_indicator_fg   => fg_rgb(220, 215, 255),  # Light lavender text
        column_indicator_bg   => bg_rgb(75, 60, 140),    # Purple accent
        column_indicator_edge => fg_rgb(75, 60, 140),    # Matches bg for powerline arrow

        # Cursor line (subtle highlight)
        cursor_line_bg => bg_rgb(41, 46, 66),

        # Cursor column (vertical highlight for crosshair effect)
        cursor_col_bg => bg_rgb(45, 50, 70),

        # Empty lines (beyond end of file)
        empty_line_bg => bg_rgb(20, 21, 30),

        # Cursor color
        cursor_color => '#7aa2f7',  # Soft blue

        # Menu bar
        menu_fg      => fg_rgb(169, 177, 214),
        menu_bg      => bg_rgb(36, 40, 59),
        menu_bg_fg   => fg_rgb(36, 40, 59),       # Menu bg as foreground (for pill edges)
        menu_hotkey  => fg_rgb(125, 207, 255),    # Cyan accent
        menu_active_fg => fg_rgb(122, 162, 247),  # Pill border color (accent blue)
        menu_active_bg => bg_rgb(52, 79, 138),    # Inside pill background
        menu_active_edge => fg_rgb(52, 79, 138),  # Active pill bg as fg (for edges)
        menu_active_text => fg_rgb(255, 255, 255), # Text inside active pill
        menu_pill_fg => fg_rgb(65, 72, 104),      # Inactive pill border (subtle)
        menu_pill_bg => bg_rgb(45, 51, 74),       # Inactive pill background
        menu_pill_edge => fg_rgb(45, 51, 74),     # Inactive pill bg as fg (for edges)
        menu_pill_text => fg_rgb(169, 177, 214), # Text inside inactive pill

        # Dropdown menu
        dropdown_fg  => fg_rgb(169, 177, 214),
        dropdown_bg  => bg_rgb(36, 40, 59),
        dropdown_selected_fg => fg_rgb(255, 255, 255),
        dropdown_selected_bg => bg_rgb(52, 79, 138),  # Darker blue for contrast
        dropdown_border => fg_rgb(61, 66, 91),
        dropdown_shortcut => fg_rgb(86, 95, 137),

        # Status bar
        status_fg    => fg_rgb(169, 177, 214),
        status_bg    => bg_rgb(36, 40, 59),
        status_bg_fg => fg_rgb(36, 40, 59),     # Status bg as foreground
        status_accent => fg_rgb(125, 207, 255), # Cyan
        status_dim    => fg_rgb(100, 106, 134), # Dimmed text for unfocused input
        # Status bar segments
        status_file_fg   => fg_rgb(255, 255, 255),
        status_file_bg   => bg_rgb(52, 79, 138),    # Blue segment
        status_file_edge => fg_rgb(52, 79, 138),
        status_pos_fg    => fg_rgb(255, 255, 255),
        status_pos_bg    => bg_rgb(86, 95, 137),    # Muted segment
        status_pos_edge  => fg_rgb(86, 95, 137),
        status_modified_fg => fg_rgb(224, 175, 104), # Yellow for modified
        # Status bar pills
        pill_toggle_on_fg   => fg_rgb(255, 255, 255),
        pill_toggle_on_bg   => bg_rgb(52, 79, 138),    # Blue (same as file segment)
        pill_toggle_on_edge => fg_rgb(52, 79, 138),
        pill_toggle_off_fg  => fg_rgb(148, 155, 185),   # Readable but subdued
        pill_toggle_off_bg  => bg_rgb(52, 59, 86),      # Slightly lighter for contrast
        pill_toggle_off_edge => fg_rgb(52, 59, 86),
        pill_action_fg      => fg_rgb(192, 202, 245),
        pill_action_bg      => bg_rgb(52, 59, 86),      # Neutral
        pill_action_edge    => fg_rgb(52, 59, 86),
        pill_palette_fg     => fg_rgb(255, 255, 255),    # Bright white text
        pill_palette_bg     => bg_rgb(86, 119, 252),    # Bold blue background
        pill_palette_edge   => fg_rgb(86, 119, 252),

        # Dialog
        dialog_fg    => fg_rgb(192, 202, 245),
        dialog_bg    => bg_rgb(36, 40, 59),
        dialog_border => fg_rgb(61, 66, 91),
        dialog_input_fg => fg_rgb(255, 255, 255),
        dialog_input_bg => bg_rgb(26, 27, 38),

        # Search highlights
        match_fg     => fg_rgb(255, 255, 255),  # White text for visibility
        match_bg     => bg_rgb(80, 70, 45),     # Amber/brown - visible but not overwhelming
        current_match_fg => fg_rgb(26, 27, 38),     # Dark text for contrast
        current_match_bg => bg_rgb(255, 200, 100),  # Bright yellow - very prominent

        # Messages
        error_fg     => fg_rgb(247, 118, 142),
        warning_fg   => fg_rgb(224, 175, 104),
        info_fg      => fg_rgb(125, 207, 255),

        # Ruler bar
        ruler_fg     => fg_rgb(86, 95, 137),     # Muted, like line numbers
        ruler_bg     => bg_rgb(30, 32, 44),      # Slightly darker than menu
        ruler_mark   => fg_rgb(61, 66, 91),      # Separator marks
        ruler_cursor_fg   => fg_rgb(255, 255, 255),
        ruler_cursor_bg   => bg_rgb(52, 79, 138),  # Matches active pill
        ruler_cursor_edge => fg_rgb(52, 79, 138),

        # VCS gutter indicators
        vcs_added    => fg_rgb(158, 206, 106),  # Green - new lines
        vcs_modified => fg_rgb(224, 175, 104),  # Yellow - modified lines
        vcs_modified_whitespace => fg_rgb(130, 115, 75),  # Dim yellow - whitespace-only changes
        vcs_deleted  => fg_rgb(247, 118, 142),  # Red - deleted lines

        # Inline diff backgrounds (expanded hunk view)
        diff_old_bg         => bg_rgb(60, 30, 30),     # Muted red background
        diff_old_cursor_bg  => bg_rgb(80, 35, 35),     # Brighter red for cursor line
        diff_old_gutter_bg  => bg_rgb(50, 25, 25),     # Darker red for gutter
        diff_old_highlight_bg => bg_rgb(110, 40, 40),  # Stronger red for changed chars
        diff_new_bg         => bg_rgb(30, 55, 30),     # Muted green background
        diff_new_cursor_bg  => bg_rgb(38, 70, 38),     # Brighter green for cursor line
        diff_new_gutter_bg  => bg_rgb(25, 45, 25),     # Darker green for gutter
        diff_new_highlight_bg => bg_rgb(40, 100, 40),  # Stronger green for changed chars

        # Tab bar
        tab_bar_bg          => bg_rgb(30, 32, 44),     # Matches ruler_bg — seamless
        tab_bar_bg_fg       => fg_rgb(30, 32, 44),     # Bar bg as foreground (for powerline edges)
        tab_active_fg       => fg_rgb(255, 255, 255),  # Bright white text
        tab_active_bg       => bg_rgb(52, 79, 138),    # Blue accent — clearly active
        tab_active_edge     => fg_rgb(52, 79, 138),    # Matches active bg for smooth transition
        tab_inactive_fg     => fg_rgb(140, 148, 190),  # Readable muted text
        tab_inactive_bg     => bg_rgb(40, 44, 62),     # Subtle, between bar and menu
        tab_inactive_edge   => fg_rgb(40, 44, 62),     # Matches inactive bg
        tab_modified_fg     => fg_rgb(224, 175, 104),  # Yellow dot for unsaved
        tab_close_fg        => fg_rgb(100, 106, 134),  # Dim close button
        tab_shortcut_fg     => fg_rgb(120, 130, 170),  # Readable hint
        tab_vcs_fg          => fg_rgb(224, 175, 104),   # VCS-changed file tint (warm amber)
        tab_baseline_ul     => "\x1b[58;2;55;60;85m",   # Underline color (SGR 58) for baseline

        # Minimap / scrollbar
        minimap_bg          => bg_rgb(22, 23, 34),     # Slightly darker than editor bg
        minimap_viewport_bg => bg_rgb(45, 50, 72),     # Highlighted viewport region
        minimap_text_fg     => fg_rgb(70, 78, 110),    # Dim text density
        minimap_separator   => fg_rgb(45, 50, 70),     # Subtle separator line
        minimap_cursor_fg   => fg_rgb(122, 162, 247),  # Cursor line indicator

        # Capture group colors (for regex find/replace)
        # Foreground: used in find input, replace input, status bar hints
        capture_group_1    => fg_rgb(130, 190, 220),  # Soft blue-cyan
        capture_group_2    => fg_rgb(140, 190, 130),  # Soft sage
        capture_group_3    => fg_rgb(210, 175, 120),  # Soft amber
        capture_group_4    => fg_rgb(175, 155, 210),  # Soft lavender
        # Background: current match capture sub-regions (bright enough for dark text)
        capture_group_1_bg => bg_rgb(100, 180, 210),  # Cyan tint
        capture_group_2_bg => bg_rgb(110, 185, 110),  # Green tint
        capture_group_3_bg => bg_rgb(210, 175, 95),   # Gold tint
        capture_group_4_bg => bg_rgb(165, 140, 205),  # Purple tint
        # Dim background: non-current match capture sub-regions (subtle tints)
        capture_group_1_dim_bg => bg_rgb(50, 80, 95),   # Dark cyan
        capture_group_2_dim_bg => bg_rgb(50, 82, 50),   # Dark green
        capture_group_3_dim_bg => bg_rgb(90, 78, 42),   # Dark gold
        capture_group_4_dim_bg => bg_rgb(72, 60, 88),   # Dark purple

        # File tree panel
        tree_bg               => bg_rgb(22, 23, 34),
        tree_focused_bg       => bg_rgb(28, 30, 44),
        tree_fg               => fg_rgb(169, 177, 214),
        tree_cursor_bg        => bg_rgb(52, 79, 138),
        tree_cursor_fg        => fg_rgb(255, 255, 255),
        tree_current_bg       => bg_rgb(45, 55, 85),
        tree_current_fg       => BOLD . fg_rgb(220, 225, 245),
        tree_dir_fg           => fg_rgb(125, 207, 255),
        tree_indent_fg        => fg_rgb(61, 66, 91),
        tree_result_dir_fg    => fg_rgb(150, 160, 195),
        tree_sticky_bg        => bg_rgb(30, 32, 44),
        tree_sticky_fg        => fg_rgb(120, 130, 165),
        tree_filter_bg        => bg_rgb(36, 40, 59),
        tree_filter_fg        => fg_rgb(192, 202, 245),
        tree_match_fg         => fg_rgb(125, 207, 255),
        tree_scrollbar_fg     => fg_rgb(86, 95, 137),
        tree_scrollbar_bg     => bg_rgb(22, 23, 34),
        tree_border_fg        => fg_rgb(61, 66, 91),
        tree_border_active_fg => fg_rgb(125, 207, 255),
        tree_border_drag_fg   => fg_rgb(125, 207, 255),
        tree_vcs_modified     => fg_rgb(224, 175, 104),
        tree_vcs_added        => fg_rgb(158, 206, 106),
        tree_vcs_untracked    => fg_rgb(158, 206, 106),
        tree_vcs_staged       => fg_rgb(138, 173, 244),
        tree_vcs_ignored      => fg_rgb(86, 95, 137),
        tree_preview_fg       => fg_rgb(140, 148, 190),

        # Syntax highlighting (Tokyo Night inspired)
        # Comments are prominent - they're documentation, not noise!
        syntax_keyword     => fg_rgb(187, 154, 247),  # Purple - control flow
        syntax_string      => fg_rgb(158, 206, 106),  # Green - string literals
        syntax_comment     => fg_rgb(150, 175, 200),  # Bold blue-gray - PROMINENT comments
        syntax_number      => fg_rgb(255, 158, 100),  # Orange - numeric literals
        syntax_function    => fg_rgb(125, 207, 255),  # Cyan - function names
        syntax_variable    => fg_rgb(224, 175, 104),  # Yellow - variables
        syntax_type        => fg_rgb(138, 173, 244),  # Light blue - types/classes
        syntax_operator    => fg_rgb(137, 221, 255),  # Light cyan - operators
        syntax_regex       => fg_rgb(245, 169, 127),  # Peach - regex
        syntax_constant    => fg_rgb(255, 158, 100),  # Orange - constants
        syntax_attribute   => fg_rgb(180, 190, 254),  # Lavender - decorators
        syntax_tag         => fg_rgb(242, 143, 173),  # Pink - HTML/JSX tags
        syntax_punctuation => fg_rgb(166, 173, 200),  # Subtle gray - brackets
        syntax_escape      => fg_rgb(245, 169, 127),  # Peach - escape sequences
        syntax_heading     => BOLD . fg_rgb(122, 162, 247),  # Bold blue - generic heading
        syntax_heading1    => BOLD . fg_rgb(100, 149, 255),  # Bright blue - h1
        syntax_heading2    => BOLD . fg_rgb(120, 155, 245),  # Blue - h2
        syntax_heading3    => BOLD . fg_rgb(140, 160, 232),  # Blue-violet - h3
        syntax_heading4    => BOLD . fg_rgb(158, 162, 218),  # Muted violet - h4
        syntax_heading5    => BOLD . fg_rgb(170, 168, 205),  # Dim lavender - h5
        syntax_heading6    => BOLD . fg_rgb(178, 175, 195),  # Gray-lavender - h6
        syntax_bold        => BOLD . fg_rgb(255, 158, 100),  # Bold orange - prose bold
        syntax_italic      => ITALIC . fg_rgb(158, 206, 106),  # Italic green - prose italic
        syntax_bold_italic => BOLD . ITALIC . fg_rgb(255, 158, 100),  # Bold+italic orange
        syntax_link        => UNDERLINE . fg_rgb(242, 143, 173),  # Underlined pink - hyperlinks
        syntax_underline   => UNDERLINE . fg_rgb(192, 202, 245),  # Underlined fg - prose underline
        syntax_strikethrough => STRIKETHROUGH . fg_rgb(130, 140, 170),  # Strikethrough dimmed
        syntax_highlight   => bg_rgb(120, 100, 30) . fg_rgb(255, 255, 220),  # Yellow highlighter pen
    });
}

sub light_theme {
    my $class = shift;

    # Catppuccin Latte inspired - warm creamy background with lavender accents
    return $class->new('light', {
        # Main text area
        fg          => fg_rgb(76, 79, 105),    # Dark blue-gray text
        bg          => bg_rgb(255, 255, 255),  # Pure white

        # Line numbers gutter
        gutter_fg   => fg_rgb(156, 160, 176),  # Overlay0
        gutter_bg   => bg_rgb(255, 255, 255),  # Match main bg
        wrap_indicator_fg => fg_rgb(188, 192, 204),  # Dim gutter color for ↪ wrap indicator

        # Selection
        selection_fg => fg_rgb(76, 79, 105),
        selection_bg => bg_rgb(188, 192, 204),  # Surface1

        # Column (rectangular) selection
        column_selection_bg => bg_rgb(200, 195, 230),  # Light purple tint
        column_cursor_bg    => bg_rgb(180, 170, 215),  # Brighter for zero-width bars
        column_indicator_fg   => fg_rgb(60, 40, 110),    # Dark purple text
        column_indicator_bg   => bg_rgb(190, 180, 230),  # Light purple accent
        column_indicator_edge => fg_rgb(190, 180, 230),  # Matches bg for powerline arrow

        # Cursor line
        cursor_line_bg => bg_rgb(231, 234, 242),

        # Cursor column (subtle vertical highlight for crosshair effect)
        cursor_col_bg => bg_rgb(235, 237, 245),

        # Empty lines (beyond end of file)
        empty_line_bg => bg_rgb(225, 228, 235),

        # Cursor color
        cursor_color => '#7287fd',  # Lavender

        # Menu bar
        menu_fg      => fg_rgb(76, 79, 105),
        menu_bg      => bg_rgb(239, 241, 245),  # Base (lighter, matches main bg)
        menu_bg_fg   => fg_rgb(239, 241, 245),  # Menu bg as foreground (for pill edges)
        menu_hotkey  => fg_rgb(30, 102, 245),   # Blue accent
        menu_active_fg => fg_rgb(114, 135, 253),  # Pill border (lavender)
        menu_active_bg => bg_rgb(114, 135, 253),  # Inside pill background
        menu_active_edge => fg_rgb(114, 135, 253), # Active pill bg as fg (for edges)
        menu_active_text => fg_rgb(255, 255, 255), # Text inside active pill
        menu_pill_fg => fg_rgb(172, 176, 190),    # Inactive pill border
        menu_pill_bg => bg_rgb(204, 208, 218),    # Inactive pill background
        menu_pill_edge => fg_rgb(204, 208, 218),  # Inactive pill bg as fg (for edges)
        menu_pill_text => fg_rgb(76, 79, 105),   # Text inside inactive pill

        # Dropdown menu
        dropdown_fg  => fg_rgb(76, 79, 105),
        dropdown_bg  => bg_rgb(230, 233, 239),
        dropdown_selected_fg => fg_rgb(239, 241, 245),
        dropdown_selected_bg => bg_rgb(114, 135, 253),
        dropdown_border => fg_rgb(172, 176, 190),
        dropdown_shortcut => fg_rgb(124, 127, 147),

        # Status bar
        status_fg    => fg_rgb(76, 79, 105),
        status_bg    => bg_rgb(220, 224, 232),
        status_bg_fg => fg_rgb(220, 224, 232),  # Status bg as foreground
        status_accent => bg_rgb(30, 102, 245),
        status_dim    => fg_rgb(156, 160, 176), # Dimmed text for unfocused input
        # Status bar segments
        status_file_fg   => fg_rgb(255, 255, 255),
        status_file_bg   => bg_rgb(114, 135, 253),  # Lavender segment
        status_file_edge => fg_rgb(114, 135, 253),
        status_pos_fg    => fg_rgb(255, 255, 255),
        status_pos_bg    => bg_rgb(156, 160, 176),  # Muted segment
        status_pos_edge  => fg_rgb(156, 160, 176),
        status_modified_fg => fg_rgb(223, 142, 29), # Yellow for modified
        # Status bar pills
        pill_toggle_on_fg   => fg_rgb(255, 255, 255),
        pill_toggle_on_bg   => bg_rgb(114, 135, 253),  # Lavender (same as file segment)
        pill_toggle_on_edge => fg_rgb(114, 135, 253),
        pill_toggle_off_fg  => fg_rgb(108, 112, 134),   # Darker text for contrast
        pill_toggle_off_bg  => bg_rgb(213, 217, 227),    # Slightly different bg
        pill_toggle_off_edge => fg_rgb(213, 217, 227),
        pill_action_fg      => fg_rgb(76, 79, 105),
        pill_action_bg      => bg_rgb(206, 210, 218),    # Neutral
        pill_action_edge    => fg_rgb(206, 210, 218),
        pill_palette_fg     => fg_rgb(255, 255, 255),     # White text
        pill_palette_bg     => bg_rgb(114, 135, 253),    # Lavender (matching file segment)
        pill_palette_edge   => fg_rgb(114, 135, 253),

        # Dialog
        dialog_fg    => fg_rgb(76, 79, 105),
        dialog_bg    => bg_rgb(239, 241, 245),
        dialog_border => fg_rgb(172, 176, 190),
        dialog_input_fg => fg_rgb(76, 79, 105),
        dialog_input_bg => bg_rgb(255, 255, 255),

        # Search highlights
        match_fg     => fg_rgb(50, 50, 60),     # Dark text for visibility
        match_bg     => bg_rgb(255, 220, 150),  # Light amber - visible but not overwhelming
        current_match_fg => fg_rgb(30, 30, 30),     # Dark text for contrast
        current_match_bg => bg_rgb(255, 180, 50),   # Bright orange-yellow - very prominent

        # Messages
        error_fg     => fg_rgb(210, 15, 57),    # Red
        warning_fg   => fg_rgb(223, 142, 29),   # Yellow
        info_fg      => fg_rgb(30, 102, 245),   # Blue

        # Ruler bar
        ruler_fg     => fg_rgb(156, 160, 176),  # Muted, like line numbers
        ruler_bg     => bg_rgb(230, 233, 239),  # Matches gutter
        ruler_mark   => fg_rgb(172, 176, 190),  # Separator marks
        ruler_cursor_fg   => fg_rgb(255, 255, 255),
        ruler_cursor_bg   => bg_rgb(114, 135, 253),  # Matches active pill
        ruler_cursor_edge => fg_rgb(114, 135, 253),

        # VCS gutter indicators (bright/saturated for visibility on white)
        vcs_added    => fg_rgb(40, 180, 80),    # Bright green - new lines
        vcs_modified => fg_rgb(230, 140, 0),    # Bright orange - modified lines
        vcs_modified_whitespace => fg_rgb(195, 175, 130),  # Dim orange - whitespace-only changes
        vcs_deleted  => fg_rgb(230, 60, 80),    # Bright red - deleted lines

        # Inline diff backgrounds (expanded hunk view)
        diff_old_bg         => bg_rgb(255, 220, 220),  # Pink-red background
        diff_old_cursor_bg  => bg_rgb(255, 200, 200),  # Deeper pink for cursor line
        diff_old_gutter_bg  => bg_rgb(245, 210, 210),  # Slightly darker for gutter
        diff_old_highlight_bg => bg_rgb(255, 160, 160),# Stronger pink for changed chars
        diff_new_bg         => bg_rgb(220, 255, 220),  # Pale green background
        diff_new_cursor_bg  => bg_rgb(200, 245, 200),  # Deeper green for cursor line
        diff_new_gutter_bg  => bg_rgb(210, 245, 210),  # Slightly darker for gutter
        diff_new_highlight_bg => bg_rgb(160, 240, 160),# Stronger green for changed chars

        # Tab bar
        tab_bar_bg          => bg_rgb(230, 233, 239),  # Matches ruler_bg — seamless
        tab_bar_bg_fg       => fg_rgb(230, 233, 239),  # Bar bg as foreground (for powerline edges)
        tab_active_fg       => fg_rgb(255, 255, 255),  # White text on accent bg
        tab_active_bg       => bg_rgb(114, 135, 253),  # Lavender accent — clearly active
        tab_active_edge     => fg_rgb(114, 135, 253),  # Matches active bg
        tab_inactive_fg     => fg_rgb(100, 104, 120),  # Muted text
        tab_inactive_bg     => bg_rgb(210, 214, 226),  # Subtle, slightly darker than bar
        tab_inactive_edge   => fg_rgb(210, 214, 226),  # Matches inactive bg
        tab_modified_fg     => fg_rgb(223, 142, 29),   # Yellow dot for unsaved
        tab_close_fg        => fg_rgb(156, 160, 176),  # Dim close button
        tab_shortcut_fg     => fg_rgb(130, 136, 156),  # Readable hint
        tab_vcs_fg          => fg_rgb(140, 90, 20),     # VCS-changed file tint
        tab_baseline_ul     => "\x1b[58;2;190;194;208m", # Underline color (SGR 58) for baseline

        # Minimap / scrollbar
        minimap_bg          => bg_rgb(240, 242, 248),  # Slightly different from main bg
        minimap_viewport_bg => bg_rgb(210, 215, 228),  # Highlighted viewport region
        minimap_text_fg     => fg_rgb(170, 175, 190),  # Dim text density
        minimap_separator   => fg_rgb(200, 204, 215),  # Subtle separator line
        minimap_cursor_fg   => fg_rgb(114, 135, 253),  # Cursor line indicator

        # Capture group colors (for regex find/replace)
        # Foreground: used in find input, replace input, status bar hints
        capture_group_1    => fg_rgb(30, 90, 160),    # Medium blue
        capture_group_2    => fg_rgb(30, 110, 60),    # Medium green
        capture_group_3    => fg_rgb(160, 90, 15),    # Medium amber
        capture_group_4    => fg_rgb(115, 40, 130),   # Medium purple
        # Background: current match capture sub-regions
        capture_group_1_bg => bg_rgb(155, 205, 235),  # Light blue
        capture_group_2_bg => bg_rgb(160, 220, 170),  # Light green
        capture_group_3_bg => bg_rgb(240, 205, 140),  # Light gold
        capture_group_4_bg => bg_rgb(205, 180, 235),  # Light purple
        # Dim background: non-current match capture sub-regions (very pale tints)
        capture_group_1_dim_bg => bg_rgb(220, 235, 250),  # Pale blue
        capture_group_2_dim_bg => bg_rgb(220, 242, 225),  # Pale green
        capture_group_3_dim_bg => bg_rgb(252, 235, 200),  # Pale gold
        capture_group_4_dim_bg => bg_rgb(235, 225, 248),  # Pale purple

        # File tree panel
        tree_bg               => bg_rgb(240, 242, 248),
        tree_focused_bg       => bg_rgb(230, 233, 242),
        tree_fg               => fg_rgb(76, 79, 105),
        tree_cursor_bg        => bg_rgb(114, 135, 253),
        tree_cursor_fg        => fg_rgb(255, 255, 255),
        tree_current_bg       => bg_rgb(195, 202, 220),
        tree_current_fg       => BOLD . fg_rgb(30, 35, 60),
        tree_dir_fg           => fg_rgb(10, 80, 190),
        tree_indent_fg        => fg_rgb(172, 176, 190),
        tree_result_dir_fg    => fg_rgb(80, 85, 105),
        tree_sticky_bg        => bg_rgb(230, 233, 239),
        tree_sticky_fg        => fg_rgb(100, 104, 120),
        tree_filter_bg        => bg_rgb(239, 241, 245),
        tree_filter_fg        => fg_rgb(76, 79, 105),
        tree_match_fg         => fg_rgb(30, 102, 209),
        tree_scrollbar_fg     => fg_rgb(156, 160, 176),
        tree_scrollbar_bg     => bg_rgb(240, 242, 248),
        tree_border_fg        => fg_rgb(172, 176, 190),
        tree_border_active_fg => fg_rgb(114, 135, 253),
        tree_border_drag_fg   => fg_rgb(114, 135, 253),
        tree_vcs_modified     => fg_rgb(140, 90, 20),
        tree_vcs_added        => fg_rgb(22, 120, 55),
        tree_vcs_untracked    => fg_rgb(22, 120, 55),
        tree_vcs_staged       => fg_rgb(30, 70, 180),
        tree_vcs_ignored      => fg_rgb(156, 160, 176),
        tree_preview_fg       => fg_rgb(130, 136, 156),

        # Syntax highlighting - high contrast for light backgrounds
        # Comments are prominent - they're documentation, not noise!
        syntax_keyword     => fg_rgb(136, 23, 152),   # Deep purple - high contrast
        syntax_string      => fg_rgb(22, 120, 55),    # Deep green - readable on white
        syntax_comment     => fg_rgb(70, 90, 120),    # Bold steel blue - PROMINENT
        syntax_number      => fg_rgb(180, 60, 10),    # Deep orange - high contrast
        syntax_function    => fg_rgb(10, 80, 190),    # Deep blue - high contrast
        syntax_variable    => fg_rgb(160, 95, 10),    # Deep amber - high contrast
        syntax_type        => fg_rgb(170, 75, 70),    # Deep flamingo - high contrast
        syntax_operator    => fg_rgb(0, 130, 180),    # Deep teal - high contrast
        syntax_regex       => fg_rgb(180, 60, 10),    # Deep orange - high contrast
        syntax_constant    => fg_rgb(180, 60, 10),    # Deep orange - high contrast
        syntax_attribute   => fg_rgb(95, 60, 190),    # Deep lavender - high contrast
        syntax_tag         => fg_rgb(180, 60, 130),   # Deep pink - high contrast
        syntax_punctuation => fg_rgb(90, 95, 115),    # Dark gray - readable
        syntax_escape      => fg_rgb(180, 60, 10),    # Deep orange - high contrast
        syntax_heading     => BOLD . fg_rgb(10, 80, 190),    # Bold deep blue - generic heading
        syntax_heading1    => BOLD . fg_rgb(10, 70, 195),    # Deep blue - h1
        syntax_heading2    => BOLD . fg_rgb(30, 65, 185),    # Blue - h2
        syntax_heading3    => BOLD . fg_rgb(55, 58, 172),    # Blue-violet - h3
        syntax_heading4    => BOLD . fg_rgb(78, 55, 155),    # Muted violet - h4
        syntax_heading5    => BOLD . fg_rgb(95, 60, 140),    # Dim purple - h5
        syntax_heading6    => BOLD . fg_rgb(108, 72, 128),   # Gray-purple - h6
        syntax_bold        => BOLD . fg_rgb(180, 60, 10),    # Bold deep orange - prose bold
        syntax_italic      => ITALIC . fg_rgb(22, 120, 55),  # Italic deep green - prose italic
        syntax_bold_italic => BOLD . ITALIC . fg_rgb(180, 60, 10),  # Bold+italic deep orange
        syntax_link        => UNDERLINE . fg_rgb(180, 60, 130),  # Underlined deep pink - hyperlinks
        syntax_underline   => UNDERLINE . fg_rgb(76, 79, 105),   # Underlined fg - prose underline
        syntax_strikethrough => STRIKETHROUGH . fg_rgb(120, 125, 140),  # Strikethrough dimmed
        syntax_highlight   => bg_rgb(255, 235, 120) . fg_rgb(50, 40, 10),   # Yellow highlighter pen
    });
}

# Get theme by name
sub get_theme {
    my ($class, $name) = @_;
    $name //= 'dark';

    if ($name eq 'light') {
        return $class->light_theme();
    }
    return $class->dark_theme();
}

# List available themes
sub available_themes {
    return ('dark', 'light');
}

1;
