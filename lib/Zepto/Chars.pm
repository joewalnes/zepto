package Zepto::Chars;
# =============================================================================
# Chars: Character set abstraction for Powerline/ASCII rendering
# =============================================================================
#
# Provides a unified interface for getting UI characters, with automatic
# fallback from Powerline/Nerd Font glyphs to ASCII when Powerline is disabled.
#
# Character categories:
#   - Rounded pills (for clickable buttons): round_left, round_right
#   - Arrow segments (for info displays): arrow_left, arrow_right
#   - Thin separators: sep_left, sep_right
#   - Icons: toggle_on, toggle_off, menu, branch, lock
#   - Box drawing: box_* (rounded when powerline, square when ASCII)
# =============================================================================

use strict;
use warnings;
use utf8;

# Powerline characters (Private Use Area E0xx)
use constant {
    PL_ARROW_RIGHT      => "\x{e0b0}",  #
    PL_ARROW_RIGHT_THIN => "\x{e0b1}",  #
    PL_ARROW_LEFT       => "\x{e0b2}",  #
    PL_ARROW_LEFT_THIN  => "\x{e0b3}",  #
    PL_ROUND_RIGHT      => "\x{e0b4}",  #
    PL_ROUND_LEFT       => "\x{e0b6}",  #
    PL_BRANCH           => "\x{e0a0}",  #
    PL_LINE_NUM         => "\x{e0a1}",  #
    PL_LOCK             => "\x{e0a2}",  #
};

# Nerd Font icons (Font Awesome section)
use constant {
    NF_MENU             => "\x{f0c9}",  #  (hamburger)
    NF_FILE             => "\x{f15b}",  #
    NF_FOLDER           => "\x{f07b}",  #
    NF_FOLDER_OPEN      => "\x{f07c}",  #
    NF_SAVE             => "\x{f0c7}",  #  (floppy disk)
    NF_QUIT             => "\x{f08b}",  #  (sign out)
    NF_SEARCH           => "\x{f002}",  #
    NF_PENCIL           => "\x{f040}",  #  (edit)
    NF_EYE              => "\x{f06e}",  #  (view)
    NF_COG              => "\x{f013}",  #
    NF_CHECK            => "\x{f00c}",  #
    NF_TIMES            => "\x{f00d}",  #
    NF_MODIFIED         => "\x{f111}",  #  (circle)
    NF_CARET_RIGHT      => "\x{f0da}",  #  (solid right triangle)
    NF_CARET_DOWN       => "\x{f0d7}",  #  (solid down triangle)
};

# Nerd Font devicons (file type icons)
use constant {
    NF_PERL             => "\x{e769}",  #  Perl
    NF_PYTHON           => "\x{e73c}",  #  Python
    NF_JAVASCRIPT       => "\x{e74e}",  #  JavaScript
    NF_TYPESCRIPT       => "\x{e628}",  #  TypeScript
    NF_RUBY             => "\x{e739}",  #  Ruby
    NF_RUST             => "\x{e7a8}",  #  Rust
    NF_GO               => "\x{e627}",  #  Go
    NF_MARKDOWN         => "\x{e73e}",  #  Markdown
    NF_HTML             => "\x{e736}",  #  HTML
    NF_CSS              => "\x{e749}",  #  CSS
    NF_SHELL            => "\x{e795}",  #  Shell/Bash
    NF_C                => "\x{e61e}",  #  C
    NF_CPP              => "\x{e61d}",  #  C++
    NF_JAVA             => "\x{e738}",  #  Java
    NF_JSON             => "\x{e60b}",  #  JSON
    NF_YAML             => "\x{e6a8}",  #  YAML
    NF_CLOSE            => "\x{f00d}",  #  (same as NF_TIMES)
};

# Simple toggle indicators (single-width, more compatible)
use constant {
    TOGGLE_ON           => "\x{25cf}",  # ● (filled circle)
    TOGGLE_OFF          => "\x{25cb}",  # ○ (empty circle)
};

# VCS gutter indicators (single column - color differentiates type)
use constant {
    VCS_ADDED           => "\x{2590}",  # ▐ Right half block (added line)
    VCS_MODIFIED        => "\x{2590}",  # ▐ Right half block (modified line)
    VCS_DELETED         => "\x{2590}",  # ▐ Right half block (deletion marker - red color)
    # Full block for expanded hunk indicator
    VCS_EXPANDED        => "\x{2588}",  # █ Full block (hunk is expanded)
    # Legacy: these were used for two-column display
    VCS_DEL_UPPER       => "\x{259d}",  # ▝ Upper right quadrant (deletion indicator, upper half)
    VCS_DEL_LOWER       => "\x{2597}",  # ▗ Lower right quadrant (deletion indicator, lower half)
};

# Unicode box drawing - rounded corners
use constant {
    BOX_ROUND_TL        => "\x{256d}",  # ╭
    BOX_ROUND_TR        => "\x{256e}",  # ╮
    BOX_ROUND_BL        => "\x{2570}",  # ╰ (curves up-right)
    BOX_ROUND_BR        => "\x{256f}",  # ╯ (curves up-left)
    BOX_HORIZONTAL      => "\x{2500}",  # ─
    BOX_VERTICAL        => "\x{2502}",  # │
};

# Standard box drawing - square corners
use constant {
    BOX_SQUARE_TL       => "\x{250c}",  # ┌
    BOX_SQUARE_TR       => "\x{2510}",  # ┐
    BOX_SQUARE_BL       => "\x{2514}",  # └
    BOX_SQUARE_BR       => "\x{2518}",  # ┘
};

# Character mappings: powerline => ascii fallback
my %CHARS = (
    # Rounded pills (for clickable buttons)
    # ASCII fallback uses spaces to extend background as rectangles
    round_left          => [ PL_ROUND_LEFT,       ' '  ],
    round_right         => [ PL_ROUND_RIGHT,      ' '  ],

    # Arrow segments (for informational displays)
    arrow_left          => [ PL_ARROW_LEFT,       '<'  ],
    arrow_right         => [ PL_ARROW_RIGHT,      '>'  ],

    # Thin separators
    sep_left            => [ PL_ARROW_LEFT_THIN,  '|'  ],
    sep_right           => [ PL_ARROW_RIGHT_THIN, '|'  ],

    # Git/status icons
    branch              => [ PL_BRANCH,           'Y'  ],
    line_num            => [ PL_LINE_NUM,         ':'  ],
    lock                => [ PL_LOCK,             '#'  ],

    # Toggle icons (for menu items) - simple single-width
    toggle_on           => [ TOGGLE_ON,           '*' ],  # ●
    toggle_off          => [ TOGGLE_OFF,          ' ' ],  # ○

    # Menu icon
    menu                => [ NF_MENU,             "\x{2022}"  ],  # • bullet

    # Menu header icons - fallback to bullet
    menu_file           => [ NF_FILE,             "\x{2022}"  ],
    menu_edit           => [ NF_PENCIL,           "\x{2022}"  ],
    menu_search         => [ NF_SEARCH,           "\x{2022}"  ],
    menu_view           => [ NF_EYE,              "\x{2022}"  ],

    # File/folder icons - fallback to bullet
    file                => [ NF_FILE,             "\x{2022}"  ],
    folder              => [ NF_FOLDER,           "\x{2022}"  ],
    folder_open         => [ NF_FOLDER_OPEN,      "\x{2022}"  ],
    save                => [ NF_SAVE,             "\x{2022}"  ],
    quit                => [ NF_QUIT,             "\x{2022}"  ],

    # Action icons - fallback to bullet
    search              => [ NF_SEARCH,           "\x{2022}"  ],
    pencil              => [ NF_PENCIL,           "\x{2022}"  ],
    eye                 => [ NF_EYE,              "\x{2022}"  ],
    settings            => [ NF_COG,              "\x{2022}"  ],
    check               => [ NF_CHECK,            "\x{2713}"  ],  # ✓
    times               => [ NF_TIMES,            "\x{2717}"  ],  # ✗
    modified            => [ NF_MODIFIED,         "\x{2022}"  ],

    # VCS gutter indicators (same in both modes)
    vcs_added           => [ VCS_ADDED,           VCS_ADDED     ],  # ▐
    vcs_modified        => [ VCS_MODIFIED,        VCS_MODIFIED  ],  # ▐
    vcs_deleted         => [ VCS_DELETED,         VCS_DELETED   ],  # ▐ (red)
    vcs_expanded        => [ VCS_EXPANDED,        VCS_EXPANDED  ],  # █ (expanded hunk)
    vcs_del_upper       => [ VCS_DEL_UPPER,       VCS_DEL_UPPER ],  # ▝ (legacy)
    vcs_del_lower       => [ VCS_DEL_LOWER,       VCS_DEL_LOWER ],  # ▗ (legacy)

    # Box drawing - corners (rounded when powerline, square when not)
    box_tl              => [ BOX_ROUND_TL,        BOX_SQUARE_TL ],
    box_tr              => [ BOX_ROUND_TR,        BOX_SQUARE_TR ],
    box_bl              => [ BOX_ROUND_BL,        BOX_SQUARE_BL ],
    box_br              => [ BOX_ROUND_BR,        BOX_SQUARE_BR ],

    # Box drawing - lines (same in both modes)
    box_h               => [ BOX_HORIZONTAL,      BOX_HORIZONTAL ],
    box_v               => [ BOX_VERTICAL,        BOX_VERTICAL ],

    # Minimap separator (thin vertical line between text and minimap)
    minimap_sep         => [ BOX_VERTICAL,        '|' ],

    # Minimap VCS indicator (thinnest bar — compact to match minimap scale)
    minimap_vcs         => [ "\x{258f}",          '|' ],  # ▏ Left one eighth block

    # Word wrap continuation indicator
    wrap_indicator      => [ "\x{21AA}",          '\\' ],  # ↪ / backslash fallback

    # Tree structure (powerline → ascii)
    tree_branch         => [ "\x{251c}",          '|' ],  # ├
    tree_last           => [ BOX_ROUND_BL,        '`' ],  # ╰
    tree_vertical       => [ BOX_VERTICAL,        '|' ],  # │
    tree_dash           => [ BOX_HORIZONTAL,      '-' ],  # ─

    # Directory expand/collapse arrows (Nerd Font carets)
    tree_arrow_right    => [ NF_CARET_RIGHT,      '>' ],  #  (collapsed)
    tree_arrow_down     => [ NF_CARET_DOWN,        'v' ],  #  (expanded)
);

# Module state
my $_powerline_enabled = 1;  # Default ON

# =============================================================================
# Public API
# =============================================================================

# Enable powerline characters
sub enable {
    $_powerline_enabled = 1;
}

# Disable powerline characters (use ASCII fallbacks)
sub disable {
    $_powerline_enabled = 0;
}

# Toggle powerline on/off
sub toggle {
    $_powerline_enabled = !$_powerline_enabled;
    return $_powerline_enabled;
}

# Check if powerline is enabled
sub enabled {
    return $_powerline_enabled;
}

# Set powerline state explicitly
sub set_enabled {
    my ($class, $enabled) = @_;
    # Handle both class method and direct call
    if (ref($class) || $class !~ /::/) {
        $enabled = $class;
    }
    $_powerline_enabled = $enabled ? 1 : 0;
    return $_powerline_enabled;
}

# Get a character by name
# Returns powerline char if enabled, ASCII fallback otherwise
sub get {
    my ($class, $name) = @_;
    # Handle both class method and direct call
    if (!defined $name) {
        $name = $class;
    }

    my $entry = $CHARS{$name};
    return '' unless defined $entry;

    return $_powerline_enabled ? $entry->[0] : $entry->[1];
}

# Get multiple characters as a hash
sub get_all {
    my ($class, @names) = @_;
    my %result;
    for my $name (@names) {
        $result{$name} = $class->get($name);
    }
    return %result;
}

# =============================================================================
# Convenience accessors
# =============================================================================

sub round_left   { shift->get('round_left') }
sub round_right  { shift->get('round_right') }
sub arrow_left   { shift->get('arrow_left') }
sub arrow_right  { shift->get('arrow_right') }
sub sep_left     { shift->get('sep_left') }
sub sep_right    { shift->get('sep_right') }
sub toggle_on    { shift->get('toggle_on') }
sub toggle_off   { shift->get('toggle_off') }
sub menu         { shift->get('menu') }
sub branch       { shift->get('branch') }
sub modified     { shift->get('modified') }

sub box_tl       { shift->get('box_tl') }
sub box_tr       { shift->get('box_tr') }
sub box_bl       { shift->get('box_bl') }
sub box_br       { shift->get('box_br') }
sub box_h        { shift->get('box_h') }
sub box_v        { shift->get('box_v') }

# =============================================================================
# Helpers for building UI elements
# =============================================================================

# Create a rounded pill: RL content RR
sub pill {
    my ($class, $content) = @_;
    return $class->get('round_left') . $content . $class->get('round_right');
}

# Create an arrow segment pointing right: content AR
sub segment_right {
    my ($class, $content) = @_;
    return $content . $class->get('arrow_right');
}

# Create an arrow segment pointing left: AL content
sub segment_left {
    my ($class, $content) = @_;
    return $class->get('arrow_left') . $content;
}

# File extension to icon mapping
my %FILE_ICONS = (
    pl   => [ NF_PERL,       "\x{2022}" ],
    pm   => [ NF_PERL,       "\x{2022}" ],
    py   => [ NF_PYTHON,     "\x{2022}" ],
    js   => [ NF_JAVASCRIPT, "\x{2022}" ],
    mjs  => [ NF_JAVASCRIPT, "\x{2022}" ],
    ts   => [ NF_TYPESCRIPT, "\x{2022}" ],
    tsx  => [ NF_TYPESCRIPT, "\x{2022}" ],
    jsx  => [ NF_JAVASCRIPT, "\x{2022}" ],
    rb   => [ NF_RUBY,       "\x{2022}" ],
    rs   => [ NF_RUST,       "\x{2022}" ],
    go   => [ NF_GO,         "\x{2022}" ],
    md   => [ NF_MARKDOWN,   "\x{2022}" ],
    html => [ NF_HTML,       "\x{2022}" ],
    htm  => [ NF_HTML,       "\x{2022}" ],
    css  => [ NF_CSS,        "\x{2022}" ],
    sh   => [ NF_SHELL,      "\x{2022}" ],
    bash => [ NF_SHELL,      "\x{2022}" ],
    zsh  => [ NF_SHELL,      "\x{2022}" ],
    c    => [ NF_C,          "\x{2022}" ],
    h    => [ NF_C,          "\x{2022}" ],
    cpp  => [ NF_CPP,        "\x{2022}" ],
    hpp  => [ NF_CPP,        "\x{2022}" ],
    java => [ NF_JAVA,       "\x{2022}" ],
    json => [ NF_JSON,       "\x{2022}" ],
    yml  => [ NF_YAML,       "\x{2022}" ],
    yaml => [ NF_YAML,       "\x{2022}" ],
    t    => [ NF_PERL,       "\x{2022}" ],  # Perl test files
);

# Get file type icon for a filename
# Returns the appropriate nerd font icon or ASCII fallback
sub file_icon {
    my ($class, $filename) = @_;
    return $_powerline_enabled ? NF_FILE : "\x{2022}" unless defined $filename;

    # Extract extension
    my ($ext) = $filename =~ /\.([^.]+)$/;
    $ext = lc($ext // '');

    my $entry = $FILE_ICONS{$ext};
    if ($entry) {
        return $_powerline_enabled ? $entry->[0] : $entry->[1];
    }

    # Default file icon
    return $_powerline_enabled ? NF_FILE : "\x{2022}";
}

# Create a horizontal line of specified width
sub hline {
    my ($class, $width) = @_;
    return $class->get('box_h') x $width;
}

# Create a box top: TL + hline + TR
sub box_top {
    my ($class, $width) = @_;
    return $class->get('box_tl') . $class->hline($width - 2) . $class->get('box_tr');
}

# Create a box bottom: BL + hline + BR
sub box_bottom {
    my ($class, $width) = @_;
    return $class->get('box_bl') . $class->hline($width - 2) . $class->get('box_br');
}

1;
