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

    return $class->new('dark', {
        # Main text area
        fg          => fg_rgb(212, 212, 212),  # Light gray text
        bg          => bg_rgb(30, 30, 46),     # Deep blue-gray background

        # Line numbers gutter
        gutter_fg   => fg_rgb(98, 98, 118),    # Dimmed
        gutter_bg   => bg_rgb(24, 24, 37),     # Slightly darker

        # Selection
        selection_fg => fg_rgb(255, 255, 255),
        selection_bg => bg_rgb(68, 68, 102),   # Purple-ish highlight

        # Cursor line (subtle highlight)
        cursor_line_bg => bg_rgb(40, 40, 56),

        # Cursor color (electric yellow - maximum visibility)
        cursor_color => '#FFFF00',  # Pure bright yellow for OSC 12

        # Menu bar
        menu_fg      => fg_rgb(200, 200, 220),
        menu_bg      => bg_rgb(45, 45, 65),
        menu_hotkey  => fg_rgb(136, 192, 208), # Cyan accent
        menu_active_fg => fg_rgb(255, 255, 255),
        menu_active_bg => bg_rgb(80, 80, 120),

        # Dropdown menu
        dropdown_fg  => fg_rgb(200, 200, 220),
        dropdown_bg  => bg_rgb(55, 55, 75),
        dropdown_selected_fg => fg_rgb(255, 255, 255),
        dropdown_selected_bg => bg_rgb(100, 100, 140),
        dropdown_border => fg_rgb(80, 80, 100),
        dropdown_shortcut => fg_rgb(140, 140, 160),

        # Status bar
        status_fg    => fg_rgb(180, 180, 200),
        status_bg    => bg_rgb(45, 45, 65),
        status_accent => fg_rgb(136, 192, 208), # Cyan

        # Dialog
        dialog_fg    => fg_rgb(212, 212, 212),
        dialog_bg    => bg_rgb(50, 50, 70),
        dialog_border => fg_rgb(100, 100, 130),
        dialog_input_fg => fg_rgb(255, 255, 255),
        dialog_input_bg => bg_rgb(35, 35, 50),

        # Search highlights
        match_fg     => fg_rgb(30, 30, 46),
        match_bg     => bg_rgb(229, 192, 123),  # Yellow highlight

        # Messages
        error_fg     => fg_rgb(255, 100, 100),
        warning_fg   => fg_rgb(229, 192, 123),
        info_fg      => fg_rgb(136, 192, 208),
    });
}

sub light_theme {
    my $class = shift;

    return $class->new('light', {
        # Main text area
        fg          => fg_rgb(90, 90, 90),     # Medium gray text (lighter so cursor stands out)
        bg          => bg_rgb(253, 253, 253),  # Off-white background

        # Line numbers gutter
        gutter_fg   => fg_rgb(150, 150, 160),
        gutter_bg   => bg_rgb(243, 243, 243),

        # Selection
        selection_fg => fg_rgb(0, 0, 0),
        selection_bg => bg_rgb(180, 210, 250),  # Light blue highlight

        # Cursor line
        cursor_line_bg => bg_rgb(245, 245, 250),

        # Cursor color (bright red - #000000 pure black doesn't work in some terminals)
        cursor_color => '#FF0000',  # Bright red for OSC 12

        # Menu bar
        menu_fg      => fg_rgb(60, 60, 70),
        menu_bg      => bg_rgb(235, 235, 240),
        menu_hotkey  => fg_rgb(0, 100, 180),   # Blue accent
        menu_active_fg => fg_rgb(255, 255, 255),
        menu_active_bg => bg_rgb(0, 100, 180),

        # Dropdown menu (light gray background for contrast with editor)
        dropdown_fg  => fg_rgb(30, 30, 40),
        dropdown_bg  => bg_rgb(240, 240, 245),
        dropdown_selected_fg => fg_rgb(255, 255, 255),
        dropdown_selected_bg => bg_rgb(0, 100, 180),
        dropdown_border => fg_rgb(180, 180, 190),
        dropdown_shortcut => fg_rgb(100, 100, 120),

        # Status bar
        status_fg    => fg_rgb(80, 80, 100),
        status_bg    => bg_rgb(235, 235, 240),
        status_accent => fg_rgb(0, 100, 180),

        # Dialog
        dialog_fg    => fg_rgb(50, 50, 50),
        dialog_bg    => bg_rgb(255, 255, 255),
        dialog_border => fg_rgb(180, 180, 200),
        dialog_input_fg => fg_rgb(0, 0, 0),
        dialog_input_bg => bg_rgb(250, 250, 255),

        # Search highlights
        match_fg     => fg_rgb(0, 0, 0),
        match_bg     => bg_rgb(255, 230, 100),

        # Messages
        error_fg     => fg_rgb(200, 50, 50),
        warning_fg   => fg_rgb(180, 120, 0),
        info_fg      => fg_rgb(0, 100, 180),
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
