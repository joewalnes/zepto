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
    UNDERLINE => "\x1b[4m",
    REVERSE => "\x1b[7m",
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

        # Selection
        selection_fg => fg_rgb(192, 202, 245),
        selection_bg => bg_rgb(51, 70, 124),   # Deep blue highlight

        # Cursor line (subtle highlight)
        cursor_line_bg => bg_rgb(41, 46, 66),

        # Cursor color
        cursor_color => '#7aa2f7',  # Soft blue

        # Menu bar
        menu_fg      => fg_rgb(169, 177, 214),
        menu_bg      => bg_rgb(36, 40, 59),
        menu_hotkey  => fg_rgb(125, 207, 255), # Cyan accent
        menu_active_fg => fg_rgb(255, 255, 255),
        menu_active_bg => bg_rgb(52, 79, 138),  # Darker blue for contrast

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
        status_accent => fg_rgb(125, 207, 255), # Cyan

        # Dialog
        dialog_fg    => fg_rgb(192, 202, 245),
        dialog_bg    => bg_rgb(36, 40, 59),
        dialog_border => fg_rgb(61, 66, 91),
        dialog_input_fg => fg_rgb(255, 255, 255),
        dialog_input_bg => bg_rgb(26, 27, 38),

        # Search highlights
        match_fg     => fg_rgb(26, 27, 38),
        match_bg     => bg_rgb(224, 175, 104),  # Warm yellow

        # Messages
        error_fg     => fg_rgb(247, 118, 142),
        warning_fg   => fg_rgb(224, 175, 104),
        info_fg      => fg_rgb(125, 207, 255),
    });
}

sub light_theme {
    my $class = shift;

    # Catppuccin Latte inspired - warm creamy background with lavender accents
    return $class->new('light', {
        # Main text area
        fg          => fg_rgb(76, 79, 105),    # Dark blue-gray text
        bg          => bg_rgb(239, 241, 245),  # Warm light gray (Base)

        # Line numbers gutter
        gutter_fg   => fg_rgb(156, 160, 176),  # Overlay0
        gutter_bg   => bg_rgb(230, 233, 239),  # Mantle

        # Selection
        selection_fg => fg_rgb(76, 79, 105),
        selection_bg => bg_rgb(188, 192, 204),  # Surface1

        # Cursor line
        cursor_line_bg => bg_rgb(231, 234, 242),

        # Cursor color
        cursor_color => '#7287fd',  # Lavender

        # Menu bar
        menu_fg      => fg_rgb(76, 79, 105),
        menu_bg      => bg_rgb(220, 224, 232),  # Surface0
        menu_hotkey  => fg_rgb(30, 102, 245),   # Blue accent
        menu_active_fg => fg_rgb(239, 241, 245),
        menu_active_bg => bg_rgb(114, 135, 253), # Lavender

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
        status_accent => bg_rgb(30, 102, 245),

        # Dialog
        dialog_fg    => fg_rgb(76, 79, 105),
        dialog_bg    => bg_rgb(239, 241, 245),
        dialog_border => fg_rgb(172, 176, 190),
        dialog_input_fg => fg_rgb(76, 79, 105),
        dialog_input_bg => bg_rgb(255, 255, 255),

        # Search highlights
        match_fg     => fg_rgb(76, 79, 105),
        match_bg     => bg_rgb(223, 142, 29),   # Yellow/peach

        # Messages
        error_fg     => fg_rgb(210, 15, 57),    # Red
        warning_fg   => fg_rgb(223, 142, 29),   # Yellow
        info_fg      => fg_rgb(30, 102, 245),   # Blue
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
