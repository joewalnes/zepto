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
use File::Basename ();
use File::Spec;
use Zepto::Chars;
use Zepto::CommandRegistry;
use Zepto::FileTree;
use Zepto::Minimap;
use Zepto::Terminal;

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
    BOX_HORIZONTAL_DOWN => "\x{252C}", # ┬
    BOX_HORIZONTAL_UP   => "\x{2534}", # ┴
    BOX_CROSS           => "\x{253C}", # ┼
};

# Modifier-key glyph used in shortcut hints (status bar pills, palette,
# dialog titles). Plain Unicode, not a Nerd Font glyph — used unconditionally
# regardless of Zepto::Chars->enabled(), so it lives here rather than in
# Zepto::Chars (which is specifically for Nerd Font/ASCII fallback pairs).
use constant CTRL_GLYPH => "\x{2303}";  # ⌃

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
    # Below this terminal width, the minimap auto-hides regardless of how
    # much room the dynamic MIN_TEXT_WIDTH check would otherwise leave it.
    # At 40 cols (the documented floor for essential chrome — see
    # docs/UI_GUIDELINES.md "surviving down to ~40 cols") a minimap is
    # barely legible at that zoom and crowds out content/status bar space
    # that matters more. 60 sits a tier above that floor, matching the
    # pattern of reserving 40 cols for must-survive elements (status bar,
    # tab bar hints) and dropping purely-decorative/supplementary ones
    # (minimap) earlier. See bugs.md / QA-REG-177.
    MINIMAP_MIN_COLS      => 60,
};


# Tab width for visual rendering. TAB_WIDTH is the back-compat fallback
# for callers that don't have the user's preference handy (e.g. direct
# unit-test calls). The *effective* width actually used by
# _expand_tabs/_char_to_visual_col/visual_to_char_col is $_tab_width
# below, which render() syncs from $prefs->tab_width() once per render
# pass -- mirrors how $_nerd_font_enabled is synced from prefs in
# Zepto::Chars (see "Sync Chars module with prefs" in render() below).
# Callers that already have the width in hand (WrapMap.pm) can also pass
# it explicitly as the trailing argument to bypass the package state.
use constant TAB_WIDTH => 4;

# Effective tab width for the current render pass. Set via set_tab_width()
# (called from render() below); read as the default by the tab-expansion
# helpers when no explicit width is passed. NEVER assign 0 or negative
# here -- set_tab_width() guards against that so a corrupt preference
# can't wedge every subsequent tab calculation.
my $_tab_width = TAB_WIDTH;

# Set the effective tab width used by tab-expansion helpers below when no
# explicit width argument is given. Call once per render pass. Falls back
# to TAB_WIDTH for any invalid (<1) value so a bad preference can never
# divide-by-zero or produce a negative expansion.
sub set_tab_width {
    my ($class, $width) = @_;
    # Handle both class-method (Zepto::Renderer->set_tab_width(4)) and
    # direct-call (Zepto::Renderer::set_tab_width(4)) styles, matching
    # Zepto::Chars::set_enabled's convention.
    if (ref($class) || $class !~ /::/) {
        $width = $class;
    }
    $width = TAB_WIDTH unless defined $width && $width =~ /^\d+$/ && $width >= 1;
    $_tab_width = $width;
    return $_tab_width;
}

# Command palette sizing: width tiers (adapts to terminal width/mode) and
# visible-item-count bounds. Used by both _render_command_palette and the
# cursor-positioning code that must mirror its layout exactly.
use constant {
    PALETTE_WIDTH_WIDE    => 120,  # File pickers (find-in-files/files/recent): wide for long paths
    PALETTE_WIDTH_MEDIUM  => 80,   # Wide terminal (>=120 cols): moderately wider
    PALETTE_WIDTH_NARROW  => 60,   # Standard terminal: default width
    PALETTE_WIDTH_MIN     => 30,   # Absolute minimum palette width
    PALETTE_MAX_ITEMS_MIN => 5,    # Fewest visible result rows regardless of terminal height
    PALETTE_MAX_ITEMS_MAX => 30,   # Most visible result rows regardless of terminal height
    PALETTE_SHORTCUT_WIDTH_MIN => 8,  # Floor for shortcut-hint column before truncation
};

# Completion dropdown menu width bounds
use constant {
    COMPLETION_MENU_WIDTH_MAX => 50,
    COMPLETION_MENU_WIDTH_MIN => 15,
};

# Find/replace bar input field sizing
use constant {
    FIND_BAR_RIGHT_SIDE_BASE_WIDTH => 45,  # ".* ^R" + "Aa ^C" + "X Esc" + "check Enter" + spaces
    FIND_INPUT_WIDTH_MIN           => 8,
    FIND_INPUT_WIDTH_MAX           => 40,  # Cap at reasonable width
};

# Footer input field sizing (goto-line pill, generic prompts)
use constant {
    FOOTER_INPUT_WIDTH_GOTO_LINE => 10,
    FOOTER_INPUT_WIDTH_WIDE_MIN  => 20,
    FOOTER_INPUT_WIDTH_DEFAULT   => 12,
};

# Column ruler: mark every Nth column (e.g. |10, |20, |30...)
use constant RULER_MARK_INTERVAL => 10;

# Terminal display width of a single character.
# Returns 2 for wide chars (CJK, emoji), 0 for control/combining, 1 otherwise.
# Based on Unicode East Asian Width property (EAW=W or F only).
# Results are memoized by codepoint to avoid repeated range checks.
my %_cdw_cache;
sub _char_display_width {
    my $ord = ord($_[0]);
    # Fast path: printable ASCII (covers ~99% of typical source code)
    return 1 if $ord >= 0x20 && $ord < 0x7F;
    return $_cdw_cache{$ord} if exists $_cdw_cache{$ord};
    my $w = _compute_char_width($ord);
    $_cdw_cache{$ord} = $w;
    return $w;
}
sub _compute_char_width {
    my ($ord) = @_;
    return 0 if $ord < 0x20;       # control chars
    return 1 if $ord < 0x1100;     # Latin, Cyrillic, etc.
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

# Truncate a string with ellipsis if it exceeds $max_width characters.
# mode 'end' (default): truncate end, append ellipsis
# mode 'start': truncate start, prepend ellipsis
# In list context, also returns $trim_offset: the number of characters
# removed from the FRONT of the original string (0 if untruncated, and
# always 0 in 'end' mode since that mode never trims the front). Callers
# that need to remap positions in the original string to columns in the
# truncated display string (e.g. search-match highlight columns) use
# this instead of re-deriving the same arithmetic themselves.
sub _ellipsis {
    my ($str, $max_width, $mode) = @_;
    return wantarray ? ($str, 0) : $str if length($str) <= $max_width;
    if (($mode // 'end') eq 'start') {
        my $trim_offset = length($str) - $max_width + 1;
        my $result = "\x{2026}" . substr($str, $trim_offset);
        return wantarray ? ($result, $trim_offset) : $result;
    }
    my $result = substr($str, 0, $max_width - 1) . "\x{2026}";
    return wantarray ? ($result, 0) : $result;
}

# Resolve a line's background color from cursor/diff-hunk state, in
# priority order: cursor+hunk > cursor-only > hunk-only > normal.
# Shared by gutter rendering and content rendering so the four states
# can't drift out of sync between call sites (see bugs.md "Scorecard
# audit round 3" — DRY finding).
sub _resolve_line_bg {
    my ($theme, $is_cursor_line, $is_hunk_line) = @_;
    return $theme->color('diff_new_cursor_bg') if $is_cursor_line && $is_hunk_line;
    return $theme->color('cursor_line_bg')     if $is_cursor_line;
    return $theme->color('diff_new_bg')        if $is_hunk_line;
    return $theme->color('bg');
}

# Bound on the tab-expansion memo cache (see _expand_tabs() below). Cleared
# wholesale once exceeded, mirroring Highlighter.pm's _token_cache pattern
# (which itself mirrors this file's own _table_cache "evict by clearing"
# approach) rather than introducing a full LRU. 8000 keeps memory bounded
# (each entry is a short string + a same-length arrayref of small integers)
# while comfortably covering many screenfuls of scrolling/typing through a
# large real-world file without thrashing.
use constant MAX_EXPAND_TABS_CACHE_ENTRIES => 8000;

# Expand tabs in a string to spaces, respecting tab stops
# Also returns a mapping from original char positions to visual positions
# Returns: ($expanded_string, \@char_to_visual)
# @char_to_visual[i] = visual column where character i starts
# $tab_width is optional; defaults to the current render pass's effective
# width (see set_tab_width() above).
#
# Memoized on (tab_width, text) -- Renderer.pm's main render loop
# (~2478) and diff-view old-content render (~3353) both call this once per
# visible line on EVERY render() (i.e. on essentially every keystroke), but
# the vast majority of visible lines are unchanged from the previous frame.
# Like Highlighter.pm's token cache (round 2's fix for the same class of
# problem, one file over), this is a pure memoization keyed on every input
# that can affect the output -- expansion is a pure function of exactly
# ($text, $tab_width), verified by inspection (no other state read below).
# That makes the cache self-invalidating with no separate bookkeeping:
#   - Editing a line's own content changes $text -> new key -> natural miss.
#   - Changing the tab-width preference changes $tab_width -> new key ->
#     natural miss; stale entries for the old width are simply never hit
#     again (no explicit "clear on tab-width change" needed, and no risk of
#     serving a different width's expansion under the new one).
# A cache hit only ever happens when both inputs are byte-identical to a
# previous call, in which case the pure function is guaranteed to return
# the same result. Returned arrayrefs are shared with the cache, not
# cloned -- safe because every caller (Renderer.pm's own render methods,
# plus WrapMap.pm via the public expand_tabs() wrapper) only reads
# char_to_visual entries by index/length; nothing mutates it in place.
{
    my %_expand_tabs_cache;        # tab_width => { text => [expanded, \@char_to_visual] }
    my $_expand_tabs_cache_count = 0;

    sub _expand_tabs {
        my ($text, $tab_width) = @_;
        return ('', []) unless defined $text && length($text) > 0;
        $tab_width = $_tab_width unless defined $tab_width && $tab_width >= 1;

        my $bucket = $_expand_tabs_cache{$tab_width} //= {};
        if (my $cached = $bucket->{$text}) {
            return @$cached;
        }

        my $expanded = '';
        my @char_to_visual;
        my $visual_col = 0;

        for my $i (0 .. length($text) - 1) {
            my $char = substr($text, $i, 1);
            push @char_to_visual, $visual_col;

            if ($char eq "\t") {
                # Expand to next tab stop
                my $spaces = $tab_width - ($visual_col % $tab_width);
                $expanded .= ' ' x $spaces;
                $visual_col += $spaces;
            } else {
                $expanded .= $char;
                $visual_col += _char_display_width($char);
            }
        }

        # Bound the memo cache: clear wholesale once it grows past the cap,
        # mirroring Highlighter.pm's _token_cache eviction.
        if ($_expand_tabs_cache_count >= MAX_EXPAND_TABS_CACHE_ENTRIES) {
            %_expand_tabs_cache = ();
            $_expand_tabs_cache_count = 0;
            $bucket = $_expand_tabs_cache{$tab_width} = {};
        }
        $bucket->{$text} = [$expanded, \@char_to_visual];
        $_expand_tabs_cache_count++;

        return ($expanded, \@char_to_visual);
    }

    # Test-only: drop all cached entries. Lets tests/renderer.t assert
    # cache-population behavior from a known-empty starting state without
    # depending on test execution order.
    sub _reset_expand_tabs_cache_for_tests {
        %_expand_tabs_cache = ();
        $_expand_tabs_cache_count = 0;
    }

    # Test-only: current cache size, for asserting eviction behavior.
    sub _expand_tabs_cache_size_for_tests {
        return $_expand_tabs_cache_count;
    }
}

# Convert a character position to visual column
# $tab_width is optional; defaults to the current render pass's effective
# width (see set_tab_width() above).
sub _char_to_visual_col {
    my ($text, $char_pos, $tab_width) = @_;
    return 0 unless defined $text && $char_pos > 0;
    $tab_width = $_tab_width unless defined $tab_width && $tab_width >= 1;

    my $visual_col = 0;
    my $len = length($text);

    # Walk through actual characters (tabs expand)
    my $walk = $char_pos < $len ? $char_pos : $len;
    for my $i (0 .. $walk - 1) {
        my $char = substr($text, $i, 1);
        if ($char eq "\t") {
            $visual_col += $tab_width - ($visual_col % $tab_width);
        } else {
            $visual_col += _char_display_width($char);
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
# $tab_width is optional; defaults to the current render pass's effective
# width (see set_tab_width() above).
sub visual_to_char_col {
    my ($text, $visual_col, $tab_width) = @_;
    return 0 unless defined $text && length($text) > 0;
    return 0 if $visual_col <= 0;
    $tab_width = $_tab_width unless defined $tab_width && $tab_width >= 1;

    my $current_visual = 0;
    my $len = length($text);

    for my $i (0 .. $len - 1) {
        my $char = substr($text, $i, 1);
        my $char_width;

        if ($char eq "\t") {
            $char_width = $tab_width - ($current_visual % $tab_width);
        } else {
            $char_width = _char_display_width($char);
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

# =============================================================================
# Public tab-expansion API
# =============================================================================
# Thin, no-underscore wrappers around _expand_tabs()/_char_to_visual_col()
# for callers in *other* modules (e.g. WrapMap.pm's wrap-layout math, which
# needs the same char<->visual column mapping this module already computes).
# Underscore-prefixed subs are private-by-convention (docs/CODE_QUALITY.md
# "Naming") and were previously reached directly via full package
# qualification from WrapMap.pm — a layering violation with no compile-time
# enforcement (see bugs.md "WrapMap.pm reaches into Renderer.pm's private
# functions"). These wrappers are the supported entry point instead; they
# just forward args, with no behavior change. Called the same way as the
# private functions they wrap (plain function call, not a method call —
# e.g. Zepto::Renderer::expand_tabs($text, $tab_width)).
sub expand_tabs {
    return _expand_tabs(@_);
}

sub char_to_visual_col {
    return _char_to_visual_col(@_);
}

# Store and retrieve tab bar button positions for click handling
# Each entry: { start => $x, end => $x, index => $tab_idx, type => 'tab'|'close' }
{
    my $_tab_bar_buttons = [];
    sub _set_tab_bar_buttons { shift; $_tab_bar_buttons = shift; }
    sub get_tab_bar_buttons { return @{$_tab_bar_buttons}; }
}

# Cache for tab bar rendering — avoid recalculating pill widths and truncation every frame
{
    my $_tab_bar_cache_key = '';
    my $_tab_bar_cache_str = '';
    my $_tab_bar_cache_buttons;
    sub _tab_bar_cache_get {
        my ($class, $key) = @_;
        return undef unless $key eq $_tab_bar_cache_key;
        $class->_set_tab_bar_buttons($_tab_bar_cache_buttons);
        return $_tab_bar_cache_str;
    }
    sub _tab_bar_cache_set {
        my ($class, $key, $str, $buttons) = @_;
        $_tab_bar_cache_key = $key;
        $_tab_bar_cache_str = $str;
        $_tab_bar_cache_buttons = $buttons;
    }
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
    return 0 if $cols < MINIMAP_MIN_COLS;
    my $tentative_text = $cols - $tree_width - $gutter_width - MINIMAP_WIDTH;
    return $tentative_text >= MIN_TEXT_WIDTH ? MINIMAP_WIDTH : 0;
}

# Calculate the find/replace bar's input field width for a given terminal
# width. Exported so Editor.pm's click/drag handlers can use the same
# calculation as the renderer for hit-testing (same convention as
# get_gutter_width above).
#
# Correctness requirement: the returned width, plus all the bar's other
# fixed-width elements (labels, pills, match-count text), must NEVER exceed
# $cols. Previously, FIND_INPUT_WIDTH_MIN was applied unconditionally as a
# floor, which could force the input field(s) wider than the actual budget
# on terminals narrower than ~90 cols with replace mode active (the 2 input
# fields share one budget, divided in half). At the very common 80-column
# terminal width, this overflowed the line by several characters on every
# replace-field keystroke (match-count text length varies with match
# count/searching state, so did the overflow). The overflow wraps onto the
# row below via the terminal's own auto-wrap, which the differential
# renderer (Editor.pm's render()) has no way to account for or clear — it
# tracks content per logical row, not per physical terminal line, and only
# re-emits rows it believes changed. The result was stacked, uncleared
# duplicate find-bar/preview rows on screen (bugs.md P0 "Find & Replace
# preview... corrupts on-screen rendering").
#
# Fix: only grow up to the usability-floor minimum when the budget actually
# allows it for every field; otherwise shrink below it (down to a hard
# floor of 1) rather than overflow.
sub find_bar_input_width {
    my ($class, $cols, $replace_active, $right_side_width) = @_;

    my $available;
    if ($replace_active) {
        $available = $cols - 2 - 5 - 1 - 8 - 1 - $right_side_width;  # " Find:" + "Replace:" + spaces
    } else {
        $available = $cols - 2 - 5 - $right_side_width;  # " Find:" only
    }

    my $num_fields = $replace_active ? 2 : 1;
    my $input_width = int($available / $num_fields);
    $input_width = FIND_INPUT_WIDTH_MAX if $input_width > FIND_INPUT_WIDTH_MAX;
    if ($input_width < FIND_INPUT_WIDTH_MIN && $available >= FIND_INPUT_WIDTH_MIN * $num_fields) {
        $input_width = FIND_INPUT_WIDTH_MIN;
    }
    $input_width = 1 if $input_width < 1;
    return $input_width;
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
    my $cell_aspect    = $args{cell_aspect}    // 2.0;

    # Sync Chars module with prefs
    if ($prefs) {
        Zepto::Chars->set_enabled($prefs->nerd_font());
    }

    # Sync effective tab width with prefs (bugs.md P1 "Tab Width
    # preference has no effect on rendering existing tab characters") --
    # without this, _expand_tabs/_char_to_visual_col/visual_to_char_col
    # always fell back to the hardcoded TAB_WIDTH=4 constant regardless
    # of what the user set in the palette.
    $class->set_tab_width($prefs ? $prefs->tab_width() : undef);

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

    # Estimate image spacer rows for minimap visibility decision.
    # Uses the NO-minimap text width to break the feedback loop:
    # spacers computed at widest width → stable minimap decision.
    my $spacer_estimate = 0;
    my $no_minimap_text_width = $cols - $tree_width - $gutter_width;
    $no_minimap_text_width = MIN_TEXT_WIDTH if $no_minimap_text_width < MIN_TEXT_WIDTH;
    if ($doc && $view && Zepto::Terminal->supports_kitty_graphics()) {
        my $est_start = $view->scroll_line();
        my $est_end = $est_start + $text_height;
        my $md_images = $class->_detect_markdown_images($doc, $est_start, $est_end);
        for my $img (values %$md_images) {
            if ($img->{width_px} && $img->{height_px}) {
                my $r = int(0.5 + ($img->{height_px} / $img->{width_px}) * $no_minimap_text_width / $cell_aspect);
                $r = 3 if $r < 3;
                $r = 20 if $r > 20;
                $spacer_estimate += $r;
            } else {
                $spacer_estimate += 8;
            }
        }
    }

    # Determine minimap width (drops before file tree at narrow widths, and
    # auto-hides entirely below MINIMAP_MIN_COLS regardless of remaining
    # room — see MINIMAP_MIN_COLS above / bugs.md QA-REG-177).
    my $show_minimap = $prefs && $prefs->show_minimap();
    my $minimap_width = 0;
    if ($show_minimap && $doc && $cols >= MINIMAP_MIN_COLS
            && ($line_count + $spacer_estimate) > $text_height) {
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
    my ($text_rows, $inline_images, $cursor_image_offset, $spacer_row_count) = $class->_render_text_area(
        $doc, $view, $theme,
        $text_height, $text_width, $gutter_width, $highlighter,
        $ui->{find_mode}, $minimap_width, $tree_width,
        $cell_aspect, $ui->{completion}, $prefs
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

    # Render completion menu overlay (dropdown)
    if ($ui->{completion} && $ui->{completion}{state} && $ui->{completion}{state} == 2) {
        my $menu_output = $class->_render_completion_menu(
            $theme, $ui->{completion}, $rows, $cols, $gutter_width, $tree_width, $text_height
        );
        $class->_merge_into_rows(\@row_buf, $menu_output, $rows);
    }

    # Build cursor positioning sequence (separate from row content)
    my $cursor_seq = '';
    if ($ui->{palette}) {
        # Position cursor in palette filter input
        # MUST match dimensions in _render_command_palette exactly
        my $palette = $ui->{palette};
        my $pal_mode = $palette->{mode} // 'commands';
        my $pal_width = $cols - 4;
        if ($pal_mode eq 'find_in_files' || $pal_mode eq 'files' || $pal_mode eq 'recent_files') {
            $pal_width = PALETTE_WIDTH_WIDE if $pal_width > PALETTE_WIDTH_WIDE;
        } elsif ($cols >= PALETTE_WIDTH_WIDE) {
            $pal_width = PALETTE_WIDTH_MEDIUM if $pal_width > PALETTE_WIDTH_MEDIUM;
        } else {
            $pal_width = PALETTE_WIDTH_NARROW if $pal_width > PALETTE_WIDTH_NARROW;
        }
        $pal_width = PALETTE_WIDTH_MIN if $pal_width < PALETTE_WIDTH_MIN;
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
        my $has_footer_row = ($pal_mode eq 'find_in_files') ? 1 : 0;
        my $max_items = $rows - 6 - $has_footer_row;
        $max_items = PALETTE_MAX_ITEMS_MIN if $max_items < PALETTE_MAX_ITEMS_MIN;
        $max_items = PALETTE_MAX_ITEMS_MAX if $max_items > PALETTE_MAX_ITEMS_MAX;
        my $pal_height = 3 + $max_items + $has_footer_row + 1;
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
            $input_width = FOOTER_INPUT_WIDTH_GOTO_LINE;
        } else {
            $prompt_len = length($input->{prompt} // '') + 2;  # +2 for leading/trailing space
            if ($input->{wide}) {
                my $hint = $input->{hint} // '';
                my $hint_str = $hint ? " ($hint)" : '';
                $input_width = $cols - $prompt_len - length($hint_str) - 2;
                $input_width = FOOTER_INPUT_WIDTH_WIDE_MIN if $input_width < FOOTER_INPUT_WIDTH_WIDE_MIN;
            } else {
                $input_width = FOOTER_INPUT_WIDTH_DEFAULT;
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
            $match_text = "\x{2191}\x{2193} " . ($current + 1) . ' of ' . $match_count;
            $match_text .= '...' if $is_searching;
        }
        # Account for capture hint width (must match _render_find_bar)
        my $capture_count = $find->{capture_count} // 0;
        my $regex_on = $find->{regex} // 0;
        my $capture_hint = '';
        if ($regex_on && $capture_count > 0) {
            $capture_hint = '$0';
            for my $i (1 .. $capture_count) {
                $capture_hint .= " \$$i";
            }
        }
        my $capture_hint_width = length($capture_hint) ? length($capture_hint) + 1 : 0;
        my $replace_active = $find->{replace_active} // 0;
        my $right_side_width = FIND_BAR_RIGHT_SIDE_BASE_WIDTH + length($match_text) + $capture_hint_width;
        my $available;
        if ($replace_active) {
            $available = $cols - 2 - 5 - 1 - 8 - 1 - $right_side_width;
        } else {
            $available = $cols - 2 - 5 - $right_side_width;
        }
        my $input_width = $replace_active ? int($available / 2) : $available;
        $input_width = FIND_INPUT_WIDTH_MIN if $input_width < FIND_INPUT_WIDTH_MIN;
        $input_width = FIND_INPUT_WIDTH_MAX if $input_width > FIND_INPUT_WIDTH_MAX;

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
        # Offset cursor for inline image spacer rows above it
        $cursor_row += ($cursor_image_offset // 0);
        $cursor_seq .= _move_to($cursor_row, $cursor_col);
        $cursor_seq .= SHOW_CURSOR;
    }

    return {
        rows             => \@row_buf,
        cursor_seq       => $cursor_seq,
        inline_images    => $inline_images,
        spacer_row_count => $spacer_row_count // 0,
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

# Render completion dropdown menu overlay
# Returns ANSI string with cursor positioning for overlay compositing
sub _render_completion_menu {
    my ($class, $theme, $completion, $rows, $cols, $gutter_width, $tree_width, $text_height) = @_;

    my $items = $completion->{menu_items} // [];
    return '' unless @$items;

    my $menu_index = $completion->{menu_index} // 0;
    my $menu_scroll = $completion->{menu_scroll} // 0;
    my $max_visible = $completion->{menu_max_visible} // 8;
    my $cursor_line = $completion->{cursor_line} // 0;
    my $cursor_col = $completion->{cursor_col} // 0;
    my $prefix_len = length($completion->{prefix} // '');

    # Calculate menu position
    # Menu appears below cursor line, or above if near bottom
    my $menu_row = $cursor_line + 3 + 1;  # +3 for tab+ruler+1-index, +1 below cursor
    # Account for scroll: cursor_line is doc line, but we need screen position
    # The menu_row here is approximate — we position relative to cursor

    my $visible_count = scalar(@$items) < $max_visible ? scalar(@$items) : $max_visible;
    my $menu_height = $visible_count + 2;  # +2 for top/bottom border

    # Flip above cursor if near bottom
    if ($menu_row + $menu_height > $rows) {
        $menu_row = $cursor_line + 3 - $menu_height;  # Above cursor
        $menu_row = 3 if $menu_row < 3;  # Don't go above text area
    }

    # Calculate menu width from item lengths
    my $max_item_len = 0;
    for my $item (@$items) {
        my $len = length($item->{text}) + 4;  # kind_char + space + text + padding
        $max_item_len = $len if $len > $max_item_len;
    }
    my $menu_width = $max_item_len + 2;  # +2 for borders
    $menu_width = COMPLETION_MENU_WIDTH_MAX if $menu_width > COMPLETION_MENU_WIDTH_MAX;
    $menu_width = COMPLETION_MENU_WIDTH_MIN if $menu_width < COMPLETION_MENU_WIDTH_MIN;

    # Position menu at cursor column (aligned to prefix start)
    my $menu_col = $tree_width + $gutter_width + ($cursor_col - $prefix_len) + 1;
    $menu_col = $tree_width + $gutter_width + 1 if $menu_col < $tree_width + $gutter_width + 1;
    # Don't overflow right edge
    if ($menu_col + $menu_width > $cols) {
        $menu_col = $cols - $menu_width;
        $menu_col = 1 if $menu_col < 1;
    }

    my $menu_bg = $theme->color('completion_menu_bg');
    my $menu_fg = $theme->color('completion_menu_fg');
    my $sel_bg = $theme->color('completion_selected_bg');
    my $sel_fg = $theme->color('completion_selected_fg');
    my $kind_fg = $theme->color('completion_kind_fg');
    my $border_fg = $theme->color('completion_border_fg');

    my $inner_width = $menu_width - 2;

    my @out;

    # Top border
    push @out, _move_to($menu_row, $menu_col);
    push @out, $menu_bg . $border_fg;
    push @out, BOX_TOP_LEFT . (BOX_HORIZONTAL x $inner_width) . BOX_TOP_RIGHT;

    # Menu items
    for my $vi (0 .. $visible_count - 1) {
        my $idx = $menu_scroll + $vi;
        last if $idx >= @$items;
        my $item = $items->[$idx];
        my $is_selected = ($idx == $menu_index);

        my $row_bg = $is_selected ? $sel_bg : $menu_bg;
        my $row_fg = $is_selected ? $sel_fg : $menu_fg;

        # Kind icon: K=keyword, W=word, P=path
        my $kind = $item->{kind} // 'word';
        my $kind_char = $kind eq 'keyword' ? 'K' : $kind eq 'path' ? 'P' : 'W';

        my $text = $item->{text};
        my $display = $kind_char . ' ' . $text;
        # Truncate to fit
        if (length($display) > $inner_width) {
            $display = substr($display, 0, $inner_width);
        }
        # Pad
        my $padding = $inner_width - length($display);

        push @out, _move_to($menu_row + 1 + $vi, $menu_col);
        push @out, $menu_bg . $border_fg . BOX_VERTICAL;
        push @out, $row_bg;
        if ($is_selected) {
            push @out, $row_fg . $display . (' ' x $padding);
        } else {
            push @out, $kind_fg . $kind_char . $row_fg . ' ' . $text;
            my $text_padding = $inner_width - length($display);
            push @out, ' ' x $text_padding if $text_padding > 0;
        }
        push @out, $menu_bg . $border_fg . BOX_VERTICAL;
    }

    # Bottom border
    push @out, _move_to($menu_row + $visible_count + 1, $menu_col);
    push @out, $menu_bg . $border_fg;
    push @out, BOX_BOTTOM_LEFT . (BOX_HORIZONTAL x $inner_width) . BOX_BOTTOM_RIGHT;
    push @out, RESET;

    return join('', @out);
}

# Render the tab bar showing open file tabs
sub _render_tab_bar {
    my ($class, $theme, $cols, $ui, $tree_width) = @_;
    $tree_width //= 0;

    my $tabs = $ui->{tabs} // [];
    my $active_idx = $ui->{active_tab_index} // 0;
    my $tab_manager = $ui->{tab_manager};

    my $hover_tab_idx = $ui->{hover_tab_index};

    # Build cache key from inputs that affect tab bar output
    my $cache_key = join("\0",
        $theme->name(), $cols, $tree_width, $active_idx, scalar(@$tabs),
        ($hover_tab_idx // -1),
        map { ($_->{display_name} // '') . ($_->{is_dirty} ? 'D' : '') . ($_->{has_vcs_changes} ? 'V' : '') } @$tabs
    );
    my $cached = $class->_tab_bar_cache_get($cache_key);
    return $cached if defined $cached;

    my @_out;

    my $tab_cols = $cols - $tree_width;  # available width for tabs

    # Tab cap shape. Originally ◢/◣ (U+25E2/25E3, geometric quadrant
    # triangles). A same-day redesign (2026-08-30, "make tabs more tabby")
    # briefly replaced these with a full-block glyph (█, U+2588) after a
    # zoomed *hangon screenshot* crop showed the triangles rendering as a
    # nearly-invisible thin wedge in one corner of the cell. That turned out
    # to be a hangon rendering bug, not a real terminal limitation: hangon's
    # screenshot renderer drew geometric-shape characters via ordinary font
    # glyph outlines (a small centered dingbat) instead of procedurally,
    # the way real terminal emulators render box-drawing/geometric-shape
    # characters — confirmed by the user's own real terminal, where these
    # triangles always rendered full-height. hangon was fixed to draw them
    # as cell-filling vector shapes (see hangon's CHANGELOG, "Fix three
    # screenshot PNG rendering bugs"), and re-verified against the fix:
    # triangles now correctly fill the cell in screenshots too. Reverted to
    # ◢/◣ accordingly. The one genuinely real, independent problem the
    # redesign also fixed — inactive/hover tabs having NO background fill
    # at all (~1.17-1.19:1 contrast against the bar) — is kept: see
    # Theme.pm's tab_inactive_bg/tab_hover_bg bump, unrelated to cap shape.
    my $TAB_CAP_LEFT  = "\x{25e2}";  # ◢ — left edge, both cap shape and
                                     # position: fg fills the lower-right
                                     # triangle of the cell, positioned as
                                     # the tab's left/opening edge.
    my $TAB_CAP_RIGHT = "\x{25e3}";  # ◣ — right/closing edge, mirror of
                                     # the above.
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
    push @_out, $bar_bg . $UL_ON;

    my $x = 0;
    my @buttons;

    # Leading space (underlined)
    push @_out, ' ';
    $x++;

    # Left scroll indicator (clickable, underlined)
    if ($show_left_arrow) {
        my $arrow = Zepto::Chars->enabled() ? "\x{25c2}" : '<';  # ◂ or <
        my $arrow_start_x = $x;
        push @_out, $theme->color('tab_inactive_fg') . $arrow . ' ';
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

        my $is_hover = defined $hover_tab_idx && $hover_tab_idx == $i && !$is_active;
        my $tab_bg = $is_active  ? $theme->color('tab_active_bg')
                   : $is_hover   ? $theme->color('tab_hover_bg')
                   :               $theme->color('tab_inactive_bg');
        my $edge_fg = $is_active ? $theme->color('tab_active_edge')
                    : $is_hover  ? $theme->color('tab_hover_edge')
                    :              $theme->color('tab_inactive_edge');

        # Left cap — underlined (part of bar territory). $edge_fg equals
        # this tab's own bg color (see Theme.pm), so the triangle's filled
        # corner reads as a solid extension of the tab's own fill.
        push @_out, $bar_bg . $edge_fg . $TAB_CAP_LEFT;
        $x++;

        # Tab interior
        my $name_color;
        if ($is_active) {
            $name_color = $theme->color('tab_active_fg');
        } elsif ($is_hover) {
            $name_color = $theme->color('tab_hover_fg');
        } else {
            $name_color = $has_vcs_changes
                ? $theme->color('tab_vcs_fg')
                : $theme->color('tab_inactive_fg');
        }

        # Active tab body: no underline (opens into ruler below)
        # Inactive tab body: underline continues (baseline runs through)
        if ($is_active) {
            push @_out, $UL_OFF . $tab_bg . $name_color;
        } else {
            push @_out, $tab_bg . $name_color;
        }

        # Space + name
        push @_out, " $name";
        $x += 1 + length($name);

        # Dirty indicator
        if ($is_dirty) {
            push @_out, ' ';
            push @_out, $theme->color('tab_modified_fg');
            push @_out, $modified_char;
            push @_out, $name_color;
            $x += 2;
        }

        # Shortcut hint for tabs 1-9 (⌥N = Alt+N to switch)
        if ($i < 9) {
            push @_out, ' ';
            push @_out, $theme->color('tab_shortcut_fg');
            my $hint = "\x{2325}" . ($i + 1);  # ⌥N
            push @_out, $hint;
            push @_out, $name_color;
            $x += 1 + length($hint);
        }

        # Close button
        push @_out, ' ';
        my $close_start_x = $x;
        push @_out, $theme->color('tab_close_fg');
        push @_out, $close_char;
        $x += 2;

        push @buttons, {
            start => $close_start_x,
            end   => $x - 1,
            index => $i,
            type  => 'close',
        };

        # Right cap — re-enable underline (back to bar territory)
        if ($is_active) {
            push @_out, $UL_ON;
        }
        push @_out, $bar_bg . $edge_fg . $TAB_CAP_RIGHT;
        $x++;

        push @buttons, {
            start => $tab_start_x,
            end   => $x - 1,
            index => $i,
            type  => 'tab',
        };

        # Gap between tabs (underlined)
        if ($vi < $last_visible) {
            push @_out, $bar_bg . ' ';
            $x++;
        }
    }

    # Right scroll indicator (clickable, underlined)
    if ($show_right_arrow) {
        my $arrow = Zepto::Chars->enabled() ? "\x{25b8}" : '>';  # ▸ or >
        my $arrow_start_x = $x;
        push @_out, $bar_bg . ' ' . $theme->color('tab_inactive_fg') . $arrow;
        $x += 2;
        push @buttons, {
            start => $arrow_start_x,
            end   => $x - 1,
            index => 0,
            type  => 'scroll_right',
        };
    }

    # Fill remaining space, with a right-aligned core-nav hint if room —
    # close tab, prev/next tab, AND quit (see docs/UI_GUIDELINES.md
    # "Discoverability Contract": core navigation needs a persistent
    # on-screen hint in the current context, and quit previously had none
    # at all here — see bugs.md).
    #
    # Text/degradation logic lives in _core_nav_hint_text(), shared with
    # the FILE_TREE-context hint row (_render_context_status_bar) so the
    # two contexts can't drift apart again. The compact tier must keep
    # fitting down to 40 cols — that property was confirmed working before
    # quit was added here and must not regress.
    my $remaining = $tab_cols - $x;
    my $hint = _core_nav_hint_text($remaining);

    if (defined $hint) {
        my $hint_width = length($hint) + 2;
        my $fill = $remaining - $hint_width;
        push @_out, $bar_bg;
        push @_out, ' ' x $fill if $fill > 0;
        push @_out, ' ' . $theme->color('tab_shortcut_fg') . $hint . ' ';
    } elsif ($remaining > 0) {
        push @_out, $bar_bg;
        push @_out, ' ' x $remaining;
    }
    push @_out, $UL_OFF . RESET;

    # Offset button positions by tree_width so mouse clicks map correctly
    if ($tree_width > 0) {
        $_->{start} += $tree_width for @buttons;
        $_->{end}   += $tree_width for @buttons;
    }

    $class->_set_tab_bar_buttons(\@buttons);

    my $result = join('', @_out);
    $class->_tab_bar_cache_set($cache_key, $result, \@buttons);
    return $result;
}

# Calculate the display width of a tab pill (not counting inter-tab gap)
# Width = left_cap(1) + " name" + [" ●"(2)] + [" ⌥N"(3)] + " ×"(2) + right_cap(1) + gap(1)
# (cap glyphs — TAB_CAP_LEFT/RIGHT, geometric triangles — are always
# exactly 1 column each, same as the earlier full-block design)
sub _calc_tab_pill_width {
    my ($name, $is_dirty, $tab_index) = @_;
    my $w = 1 + 1 + length($name) + 2 + 1 + 1;  # left_cap + space + name + " ×" + right_cap + gap
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

    my @_out;

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
    push @_out, $theme->color('ruler_bg') . $theme->color('ruler_fg');
    push @_out, ' ' x $gutter_width;

    # Calculate ruler width (text area width, excluding tree)
    my $ruler_width = $cols - $tree_width - $gutter_width;

    # Build ruler string: |10      |20      |30 ... (1-indexed columns, marks at multiples of 10)
    my $ruler = '';
    my $mark_interval = RULER_MARK_INTERVAL;
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
            push @_out, $theme->color('ruler_cursor_bg') . $theme->color('ruler_cursor_fg');
            push @_out, ' ' . $cursor_str;
            push @_out, $theme->color('ruler_bg') . $theme->color('ruler_cursor_edge') . $rr;
            push @_out, $theme->color('ruler_fg');
            # Skip past the badge width in the source ruler
            $i += $badge_width;
        } else {
            # Regular ruler character
            my $ch = substr($ruler, $i, 1);
            if ($ch eq '|') {
                push @_out, $theme->color('ruler_mark');
                push @_out, $ch;
                push @_out, $theme->color('ruler_fg');
            } else {
                push @_out, $ch;
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
            push @_out, _move_to(2, $col_start);
            push @_out, $theme->color('column_indicator_bg') . $theme->color('column_indicator_fg');
            push @_out, $label;
            push @ruler_buttons, {
                x_start => $col_start,
                x_end   => $col_start + $label_width - 1,
                action  => 'toggle_column_mode',
            };
        }
    }
    $class->_set_ruler_buttons(\@ruler_buttons);

    push @_out, CLEAR_LINE;
    push @_out, RESET;

    return join('', @_out);
}

# =============================================================================
# Inline Markdown Image Detection
# =============================================================================

# Image extensions considered renderable
my %_IMAGE_EXT = map { $_ => 1 } qw(png jpg jpeg gif bmp webp tiff tif ico);

# Cache for file existence checks: path => { exists => 0|1, time => epoch }
my %_file_exists_cache;
use constant FILE_EXISTS_CACHE_TTL => 5;  # seconds

sub _file_exists_cached {
    my ($path) = @_;
    my $now = time();
    if (my $entry = $_file_exists_cache{$path}) {
        return $entry->{exists} if ($now - $entry->{time}) < FILE_EXISTS_CACHE_TTL;
    }
    my $exists = -f $path ? 1 : 0;
    $_file_exists_cache{$path} = { exists => $exists, time => $now };
    return $exists;
}

# Cache for image dimensions: path => [width, height] or path => undef (unreadable)
my %_image_dims_cache;

# Read pixel dimensions from PNG, JPEG, GIF, or BMP file headers.
# Returns (width_px, height_px) on success, empty list on failure.
sub _get_image_dimensions {
    my ($path) = @_;

    # Return cached result
    if (exists $_image_dims_cache{$path}) {
        my $cached = $_image_dims_cache{$path};
        return $cached ? @$cached : ();
    }

    my ($w, $h);
    eval {
        open my $fh, '<:raw', $path or die "open: $!";

        # Read enough bytes to detect any supported format
        my $buf;
        read($fh, $buf, 26) or die "read: $!";

        if (length($buf) >= 24 && substr($buf, 0, 8) eq "\x89PNG\r\n\x1a\n") {
            # PNG: width at bytes 16-19, height at bytes 20-23 (big-endian u32)
            ($w, $h) = unpack('NN', substr($buf, 16, 8));
        }
        elsif (length($buf) >= 10 && substr($buf, 0, 3) eq 'GIF'
               && substr($buf, 3, 3) =~ /^8[79]a$/) {
            # GIF87a/GIF89a: width at bytes 6-7, height at bytes 8-9 (little-endian u16)
            ($w, $h) = unpack('vv', substr($buf, 6, 4));
        }
        elsif (length($buf) >= 26 && substr($buf, 0, 2) eq 'BM') {
            # BMP: width at bytes 18-21, height at bytes 22-25 (little-endian i32)
            # Height can be negative (top-down bitmap), use abs
            ($w, $h) = unpack('VV', substr($buf, 18, 8));
            $h = unpack('l<', substr($buf, 22, 4));  # signed for negative heights
            $h = abs($h) if defined $h;
        }
        elsif (length($buf) >= 2 && substr($buf, 0, 2) eq "\xFF\xD8") {
            # JPEG: scan for SOF marker
            seek($fh, 2, 0) or die "seek: $!";
            my $max_scan = 65536;
            my $scanned = 0;
            while ($scanned < $max_scan) {
                my $marker_buf;
                read($fh, $marker_buf, 2) or last;
                $scanned += 2;
                my ($b1, $b2) = unpack('CC', $marker_buf);
                last unless $b1 == 0xFF;

                # SOF markers: 0xC0-0xCF except 0xC4 (DHT) and 0xC8 (JPG)
                if ($b2 >= 0xC0 && $b2 <= 0xCF && $b2 != 0xC4 && $b2 != 0xC8) {
                    my $sof_buf;
                    read($fh, $sof_buf, 7) or last;
                    if (length($sof_buf) >= 7) {
                        # Bytes: 2 length + 1 precision + 2 height + 2 width
                        $h = unpack('n', substr($sof_buf, 3, 2));
                        $w = unpack('n', substr($sof_buf, 5, 2));
                    }
                    last;
                }

                # Skip this segment: read 2-byte length, advance
                my $len_buf;
                read($fh, $len_buf, 2) or last;
                $scanned += 2;
                my $seg_len = unpack('n', $len_buf);
                last if $seg_len < 2;
                seek($fh, $seg_len - 2, 1) or last;
                $scanned += $seg_len - 2;
            }
        }

        close $fh;
    };

    if (defined $w && defined $h && $w > 0 && $h > 0) {
        $_image_dims_cache{$path} = [$w, $h];
        return ($w, $h);
    }

    $_image_dims_cache{$path} = undef;
    return ();
}

# Detect ![alt](path) image references in visible document lines.
# Returns { doc_line => { path => abs_path, alt => text } } for valid, existing images.
# Only runs for .md/.markdown files on Kitty-capable terminals.
sub _detect_markdown_images {
    my ($class, $doc, $visible_start, $visible_end) = @_;
    my %images;

    # Only for markdown files on Kitty-capable terminals
    return \%images unless Zepto::Terminal->supports_kitty_graphics();

    my $doc_path = $doc->{path};
    return \%images unless $doc_path;
    return \%images unless $doc_path =~ /\.(?:md|markdown)$/i;

    my $doc_dir = File::Basename::dirname(File::Spec->rel2abs($doc_path));
    my $line_count = $doc->line_count();

    for my $line_num ($visible_start .. $visible_end - 1) {
        last if $line_num >= $line_count;
        my $content = $doc->get_line_content($line_num);

        # Match ![alt](path) — skip URLs and data: URIs
        while ($content =~ /!\[([^\]]*)\]\(([^)]+)\)/g) {
            my ($alt, $img_path) = ($1, $2);

            # Skip URLs and data URIs
            next if $img_path =~ m{^(?:https?://|data:)};

            # Check extension
            my ($ext) = $img_path =~ /\.(\w+)$/;
            next unless $ext && $_IMAGE_EXT{lc $ext};

            # Resolve relative paths against the markdown file's directory
            my $abs_path;
            if (File::Spec->file_name_is_absolute($img_path)) {
                $abs_path = $img_path;
            } else {
                $abs_path = File::Spec->catfile($doc_dir, $img_path);
            }

            # Check file exists (cached)
            next unless _file_exists_cached($abs_path);

            # Read pixel dimensions for aspect-ratio sizing (may be empty for
            # unsupported formats like WebP/TIFF/ICO — spacer loop falls back
            # to a default height in that case)
            my ($width_px, $height_px) = _get_image_dimensions($abs_path);

            my %img_entry = (path => $abs_path, alt => $alt);
            if (defined $width_px) {
                $img_entry{width_px}  = $width_px;
                $img_entry{height_px} = $height_px;
            }
            $images{$line_num} = \%img_entry;
            last;  # Only first image per line
        }
    }

    return \%images;
}

# Detect Markdown table regions in visible range
# Returns: { tables => [{start, end, separator, col_widths, alignments, cells}], line_to_table => {line => idx} }
{
    my %_table_cache;  # keyed by doc modification count + range

    sub _detect_markdown_tables {
        my ($class, $doc, $visible_start, $visible_end) = @_;
        my $empty = { tables => [], line_to_table => {} };

        my $doc_path = $doc->{path};
        return $empty unless $doc_path;
        return $empty unless $doc_path =~ /\.(?:md|markdown)$/i;

        my $line_count = $doc->line_count();
        return $empty if $line_count == 0;

        # Cache by content version + range
        my $cache_key = ($doc->{_content_version} // 0) . ":$visible_start:$visible_end";
        return $_table_cache{$cache_key} if exists $_table_cache{$cache_key};
        %_table_cache = () if keys %_table_cache > 8;  # evict

        # Scan for tables: expand range to capture tables partially visible
        my $scan_start = $visible_start;
        while ($scan_start > 0) {
            my $line = $doc->get_line_content($scan_start - 1);
            last unless $line =~ /^\s*\|.*\|\s*$/;
            $scan_start--;
        }
        my $scan_end = $visible_end;
        while ($scan_end < $line_count) {
            my $line = $doc->get_line_content($scan_end);
            last unless $line =~ /^\s*\|.*\|\s*$/;
            $scan_end++;
        }

        my @tables;
        my %line_to_table;
        my $i = $scan_start;

        while ($i < $scan_end && $i < $line_count) {
            my $line = $doc->get_line_content($i);
            if ($line =~ /^\s*\|.*\|\s*$/) {
                # Start of a potential table
                my $table_start = $i;
                my @raw_lines;
                my $separator = -1;

                while ($i < $line_count) {
                    my $tl = $doc->get_line_content($i);
                    last unless $tl =~ /^\s*\|.*\|\s*$/;
                    push @raw_lines, $tl;
                    # Check if this is the separator row
                    if ($separator < 0 && $tl =~ /^\s*\|[\s:|-]+\|\s*$/) {
                        $separator = $i - $table_start;
                    }
                    $i++;
                }

                # Must have header + separator (at least 2 lines, separator at row 1)
                if (@raw_lines >= 2 && $separator == 1) {
                    # Parse cells and compute column widths
                    my @all_cells;
                    my @col_widths;
                    my @alignments;

                    my @all_offsets;  # per-row: [offset_of_cell_0_in_source, ...]
                    for my $ri (0 .. $#raw_lines) {
                        my $raw = $raw_lines[$ri];
                        # Compute cell offsets in the original source line
                        my @offsets;
                        {
                            my $scan = $raw;
                            $scan =~ /^\s*\|/;
                            my $pos = length($&);  # past the leading |
                            my @parts = split(/\|/, substr($raw, $pos), -1);
                            for my $pi (0 .. $#parts) {
                                my $part = $parts[$pi];
                                # Trim leading/trailing whitespace to find cell text start
                                my $trimmed = $part;
                                $trimmed =~ s/^\s+//;
                                my $leading = length($part) - length($trimmed);
                                push @offsets, $pos + $leading;
                                $pos += length($part) + 1;  # +1 for the | separator
                            }
                        }
                        push @all_offsets, \@offsets;

                        $raw =~ s/^\s*\|\s?//;
                        $raw =~ s/\s?\|\s*$//;
                        my @cells = split(/\s*\|\s*/, $raw, -1);
                        push @all_cells, \@cells;

                        # Parse alignment from separator row
                        if ($ri == $separator) {
                            for my $ci (0 .. $#cells) {
                                my $c = $cells[$ci];
                                if ($c =~ /^:-+:$/) {
                                    $alignments[$ci] = 'center';
                                } elsif ($c =~ /-+:$/) {
                                    $alignments[$ci] = 'right';
                                } else {
                                    $alignments[$ci] = 'left';
                                }
                            }
                        }

                        # Track max widths (skip separator row for width calc)
                        if ($ri != $separator) {
                            for my $ci (0 .. $#cells) {
                                my $w = _display_width($cells[$ci]);
                                $col_widths[$ci] = $w if !defined $col_widths[$ci] || $w > $col_widths[$ci];
                            }
                        }
                    }

                    # Ensure minimum column width of 3
                    for my $ci (0 .. $#col_widths) {
                        $col_widths[$ci] = 3 if ($col_widths[$ci] // 0) < 3;
                    }

                    my $table_idx = scalar @tables;
                    push @tables, {
                        start        => $table_start,
                        end          => $table_start + $#raw_lines,
                        separator    => $separator,
                        col_widths   => \@col_widths,
                        alignments   => \@alignments,
                        cells        => \@all_cells,
                        raw_lines    => \@raw_lines,
                        cell_offsets => \@all_offsets,
                    };
                    for my $li ($table_start .. $table_start + $#raw_lines) {
                        $line_to_table{$li} = $table_idx;
                    }
                }
            } else {
                $i++;
            }
        }

        my $result = { tables => \@tables, line_to_table => \%line_to_table };
        $_table_cache{$cache_key} = $result;
        return $result;
    }
}

sub _render_table_line {
    my ($class, $table, $row_in_table, $width, $theme, $scroll_col, $highlighter, $doc_line) = @_;

    my $cells = $table->{cells}[$row_in_table];
    my $col_widths = $table->{col_widths};
    my $alignments = $table->{alignments};
    my $is_header = ($row_in_table == 0);
    my $is_separator = ($row_in_table == $table->{separator});

    my $border_fg = $theme->color('table_border_fg');
    my $bg;
    my $fg;

    if ($is_header) {
        $bg = $theme->color('table_header_bg');
        $fg = $theme->color('table_header_fg');
    } elsif ($is_separator) {
        $bg = $theme->color('bg');
        $fg = $border_fg;
    } else {
        $bg = $theme->color('bg');
        $fg = $theme->color('fg');
    }

    my $num_cols = scalar @$col_widths;
    my @out;
    push @out, $bg;

    if ($is_separator) {
        # Render: ├───┼───┼───┤
        my @sep_out;
        push @sep_out, $border_fg;
        push @sep_out, BOX_VERTICAL_RIGHT;
        for my $ci (0 .. $num_cols - 1) {
            push @sep_out, BOX_HORIZONTAL x ($col_widths->[$ci] + 2);  # +2 for padding
            push @sep_out, ($ci < $num_cols - 1) ? BOX_CROSS : BOX_VERTICAL_LEFT;
        }
        push @out, join('', @sep_out);
    } else {
        # Get syntax tokens for this line to apply within cells
        my @syntax_colors;  # maps original source char position → ANSI color
        if ($highlighter) {
            my $orig_line = $table->{raw_lines}[$row_in_table];
            my ($tokens) = $highlighter->tokenize_line($orig_line, $doc_line);
            for my $tok (@$tokens) {
                my $color = $theme->color("syntax_$tok->{type}");
                next unless $color;
                for my $c ($tok->{start} .. $tok->{end} - 1) {
                    $syntax_colors[$c] = $color;
                }
            }
        }

        # Render: │ cell │ cell │
        my @row_out;
        push @row_out, $border_fg;
        push @row_out, BOX_VERTICAL;
        my $cell_offsets = $table->{cell_offsets}[$row_in_table];
        for my $ci (0 .. $num_cols - 1) {
            my $cell_text = defined $cells->[$ci] ? $cells->[$ci] : '';
            my $cell_w = _display_width($cell_text);
            my $target_w = $col_widths->[$ci] // 3;
            my $pad = $target_w - $cell_w;
            $pad = 0 if $pad < 0;

            my $align = $alignments->[$ci] // 'left';
            my ($lpad, $rpad);
            if ($align eq 'center') {
                $lpad = int($pad / 2);
                $rpad = $pad - $lpad;
            } elsif ($align eq 'right') {
                $lpad = $pad;
                $rpad = 0;
            } else {
                $lpad = 0;
                $rpad = $pad;
            }

            push @row_out, $fg;
            push @row_out, ' ' . (' ' x $lpad);

            # Render cell text with syntax highlighting
            my $src_offset = $cell_offsets->[$ci] // 0;
            my $cell_len = length($cell_text);
            my $prev_color = '';
            for my $j (0 .. $cell_len - 1) {
                my $src_pos = $src_offset + $j;
                my $c = $syntax_colors[$src_pos] // '';
                if ($c ne $prev_color) {
                    push @row_out, $c || ($fg . $bg);
                    $prev_color = $c;
                }
                push @row_out, substr($cell_text, $j, 1);
            }
            # Reset after cell content
            push @row_out, $fg . $bg if $prev_color;

            push @row_out, (' ' x $rpad) . ' ';
            push @row_out, $border_fg;
            push @row_out, BOX_VERTICAL;
        }
        push @out, join('', @row_out);
    }

    # Compute total rendered width for scroll/truncation
    my $total_w = 1;  # left border
    for my $ci (0 .. $num_cols - 1) {
        $total_w += ($col_widths->[$ci] // 3) + 2 + 1;  # cell + padding + separator
    }

    my $rendered = join('', @out);
    return ($rendered, $total_w);
}

# Render the text area with line numbers
sub _render_text_area {
    my ($class, $doc, $view, $theme, $height, $width, $gutter_width, $highlighter, $find_mode, $minimap_width, $tree_width, $cell_aspect, $completion, $prefs) = @_;
    $minimap_width //= 0;
    $tree_width //= 0;
    $cell_aspect    //= 2.0;

    my @text_rows;

    return (\@text_rows, [], 0) unless $doc && $view;

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

    # Insert image spacer entries for inline Markdown images
    my @image_placements;
    my $cursor_image_offset = 0;
    {
        my $md_images = $class->_detect_markdown_images($doc, $visible_start, $visible_end);
        if (%$md_images) {
            my $cursor_line = $view->cursor_line();
            my @new_entries;
            for my $entry (@entries) {
                push @new_entries, $entry;
                next unless $entry && ($entry->{type} // '') eq 'doc';
                next unless defined $entry->{line};
                my $img = $md_images->{$entry->{line}};
                next unless $img;
                # Only insert spacers for first wrap segment
                next if ($entry->{wrap_index} // 0) != 0;
                # Compute aspect-ratio-correct row count (default 8 if dimensions unknown)
                my $spacer_rows;
                my $place_width = $width;  # default: full content area
                if ($img->{width_px} && $img->{height_px}) {
                    my $avail_cols = $width;
                    my $natural_rows = ($img->{height_px} / $img->{width_px}) * $avail_cols / $cell_aspect;
                    $spacer_rows = int(0.5 + $natural_rows);
                    if ($spacer_rows > 20) {
                        # Reduce width proportionally to maintain aspect ratio
                        $place_width = int(0.5 + $avail_cols * 20 / $natural_rows);
                        $place_width = 1 if $place_width < 1;
                        $spacer_rows = 20;
                    }
                    $spacer_rows = 3  if $spacer_rows < 3;
                } else {
                    $spacer_rows = 8;
                }
                for my $si (0 .. $spacer_rows - 1) {
                    push @new_entries, {
                        type         => 'image_spacer',
                        image_path   => $img->{path},
                        spacer_idx   => $si,
                        spacer_rows  => $spacer_rows,
                        source_line  => $entry->{line},
                        place_width  => $place_width,
                    };
                }
            }
            # Truncate to screen height
            splice(@new_entries, $height) if @new_entries > $height;
            # Pad with undef to fill screen
            while (@new_entries < $height) {
                push @new_entries, undef;
            }
            @entries = @new_entries;

            # Count spacer rows before cursor for offset correction
            for my $entry (@entries) {
                last unless $entry;
                last if ($entry->{type} // '') eq 'doc' && ($entry->{line} // -1) >= $cursor_line
                    && ($entry->{wrap_index} // 0) == 0;
                $cursor_image_offset++ if ($entry->{type} // '') eq 'image_spacer';
            }
        }
    }

    # Detect Markdown tables for pretty-rendering
    my $md_tables;
    my %cursor_in_table;  # table_idx => 1 if cursor is in that table
    if ($prefs && $prefs->render_markdown_tables() && $highlighter
        && ($highlighter->grammar_name() // '') eq 'Markdown') {
        $md_tables = $class->_detect_markdown_tables($doc, $visible_start, $visible_end);
        if ($md_tables && %{$md_tables->{line_to_table}}) {
            my $cursor_line = $view->cursor_line();
            if (exists $md_tables->{line_to_table}{$cursor_line}) {
                $cursor_in_table{$md_tables->{line_to_table}{$cursor_line}} = 1;
            }
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

    # Use Document's cached O(1) VCS lookup hashes (rebuilt only when diff changes)
    my $vcs_change  = $doc->{_vcs_change_lookup}   // {};
    my $vcs_deletion = $doc->{_vcs_deletion_lookup} // {};

    for my $screen_row (0 .. $height - 1) {
        my $entry = $entries[$screen_row];

        # Per-row output buffer (for differential rendering)
        my @_out = (_move_to($screen_row + 3, $tree_width + 1));

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
            push @_out, $class->_render_old_line_row(
                $doc, $view, $theme, $width, $gutter_width,
                $entry, $highlighter, \$base_highlighter, $char_hl
            );
            push @_out, $class->_render_minimap_column($minimap_data, $screen_row, $theme)
                if $minimap_width > 0;
            push @_out, CLEAR_LINE;
            push @_out, RESET;
            push @text_rows, join('', @_out);
            next;
        }

        # Handle image spacer entries (blank rows for inline Markdown images)
        if ($entry && ($entry->{type} // '') eq 'image_spacer') {
            my $bg = $theme->color('bg');
            my $gutter_bg = $theme->color('gutter_bg');
            # Blank gutter
            push @_out, $gutter_bg . (' ' x $gutter_width);
            # Blank text area
            push @_out, $bg . (' ' x $width);
            # Minimap column
            push @_out, $class->_render_minimap_column($minimap_data, $screen_row, $theme)
                if $minimap_width > 0;
            push @_out, CLEAR_LINE;
            push @_out, RESET;
            push @text_rows, join('', @_out);
            # Record placement on first spacer row
            if ($entry->{spacer_idx} == 0) {
                # Count actual spacer rows visible on screen (may be truncated)
                my $actual_rows = 1;  # this row
                for my $look ($screen_row + 1 .. $height - 1) {
                    my $e = $entries[$look];
                    last unless $e && ($e->{type} // '') eq 'image_spacer'
                        && ($e->{image_path} // '') eq $entry->{image_path};
                    $actual_rows++;
                }
                push @image_placements, {
                    path        => $entry->{image_path},
                    screen_row  => $screen_row + 3,  # 1-based, after tab+ruler
                    col         => $tree_width + $gutter_width + 1,
                    width       => $entry->{place_width} // $width,
                    height_rows => $actual_rows,
                };
            }
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
            my $chg_status = $vcs_change->{$doc_line};
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
                push @_out, $gutter_bg . $vcs_color . $vcs_char;
                push @_out, $theme->color('gutter_fg');
                push @_out, ' ' x ($gutter_width - 2);
                push @_out, $theme->color('wrap_indicator_fg');
                push @_out, Zepto::Chars->get('wrap_indicator');
            } else {
                # Has hanging indent: VCS marker + padding, ↪ goes in content indent area
                push @_out, $gutter_bg . $vcs_color . $vcs_char;
                push @_out, $theme->color('gutter_fg');
                push @_out, ' ' x ($gutter_width - 1);
            }
        }
        # Line number gutter with VCS indicator (single column)
        elsif ($doc_line < $doc->line_count()) {
            my $line_num_str = sprintf("%d", $doc_line + 1);

            # Get VCS indicator for this line (single column)
            # Due to our diff algorithm, deletions never overlap with adds/modifies
            my $del_status = $vcs_deletion->{$doc_line};
            my $chg_status = $vcs_change->{$doc_line};

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
                push @_out, $gutter_bg . $vcs_color . $vcs_char;

                # Right-align: match the sprintf padding used in normal lines
                # Normal line uses sprintf("%*d", gutter_width - 3, num) which right-aligns
                my $num_width = $gutter_width - 3;  # 1(vcs) + 1(space) + digits + 1(space) = gutter_width
                my $padded_num = sprintf("%*d", $num_width, $doc_line + 1);

                # Badge: rl + padded_num + ar
                push @_out, $gutter_bg . $theme->color('ruler_cursor_edge') . $rl;
                push @_out, $theme->color('ruler_cursor_bg') . $theme->color('ruler_cursor_fg') . $padded_num;
                # Arrow right: badge color as fg, next area color as bg
                my $next_bg = _resolve_line_bg($theme, 1, $is_hunk_line);
                push @_out, $next_bg . $theme->color('ruler_cursor_edge') . $ar;
            } else {
                # Normal line: [vcs][space][right-aligned digits][space]
                # VCS indicator first
                push @_out, $gutter_bg . $vcs_color . $vcs_char;
                # Rest of gutter
                push @_out, $gutter_bg . $theme->color('gutter_fg');
                # Use (gutter_width - 3) for digits: total = 1(vcs) + 1(space) + digits + 1(space) = gutter_width
                my $line_num = sprintf("%*d", $gutter_width - 3, $doc_line + 1);
                push @_out, ' ' . $line_num . ' ';
            }
        }
        else {
            push @_out, $theme->color('gutter_bg') . $theme->color('gutter_fg');
            push @_out, ' ' x $gutter_width;
        }

        # Background: cursor+hunk > cursor > hunk > normal
        my $line_bg = _resolve_line_bg($theme, $is_cursor_line, $is_hunk_line);
        push @_out, $line_bg . $theme->color('fg');

        # Text content

        # Pretty-render Markdown table lines (unless cursor is in this table)
        if ($md_tables && !$is_wrap_cont && $doc_line < $doc->line_count()
            && exists $md_tables->{line_to_table}{$doc_line}) {
            my $table_idx = $md_tables->{line_to_table}{$doc_line};
            if (!$cursor_in_table{$table_idx}) {
                my $table = $md_tables->{tables}[$table_idx];
                my $row_in_table = $doc_line - $table->{start};
                my ($rendered, $total_w) = $class->_render_table_line(
                    $table, $row_in_table, $width, $theme, $scroll_col,
                    $highlighter, $doc_line
                );
                push @_out, $rendered;
                my $fill = $width - $total_w;
                if ($fill > 0) {
                    my $fill_bg = $is_cursor_line ? $line_bg : $theme->color('bg');
                    push @_out, $fill_bg . (' ' x $fill);
                }
                push @_out, $class->_render_minimap_column($minimap_data, $screen_row, $theme)
                    if $minimap_width > 0;
                push @_out, CLEAR_LINE;
                push @_out, RESET;
                push @text_rows, join('', @_out);
                next;
            }
        }

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
                push @_out, $line_bg . (' ' x ($wrap_indicator_width - 1));
                push @_out, $theme->color('wrap_indicator_fg') . Zepto::Chars->get('wrap_indicator');
                push @_out, $line_bg . $theme->color('fg');
            }

            # Render with selection, syntax, match, and cursor highlighting
            push @_out, $class->_render_line_with_highlights(
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
                        push @_out, $fill_bg . (' ' x $pre) if $pre > 0;
                        push @_out, $col_sel_bg . (' ' x $sel) if $sel > 0;
                        push @_out, $fill_bg . (' ' x $post) if $post > 0;
                    } else {
                        push @_out, $fill_bg . (' ' x $fill_remaining);
                    }
                } else {
                    push @_out, $fill_bg . (' ' x $fill_remaining);
                }
            } elsif ($fill_remaining > 0) {
                # Ghost text: render inline completion hint on cursor line
                if ($is_cursor_line && $completion && $completion->{ghost_text}
                    && length($completion->{ghost_text}) > 0
                    && !$is_wrap_cont) {
                    my $ghost = $completion->{ghost_text};
                    my $ghost_len = length($ghost);
                    if ($ghost_len > $fill_remaining) {
                        $ghost = substr($ghost, 0, $fill_remaining);
                        $ghost_len = $fill_remaining;
                    }
                    my $ghost_fg = $theme->color('completion_ghost_fg');
                    push @_out, $ghost_fg . $ghost . RESET . $fill_bg;
                    my $after = $fill_remaining - $ghost_len;
                    push @_out, ' ' x $after if $after > 0;
                } else {
                    push @_out, $fill_bg . (' ' x $fill_remaining);
                }
            }
        }
        else {
            # Empty line (beyond document)
            my $empty_bg = $theme->color('empty_line_bg');
            push @_out, $empty_bg . (' ' x $width);
        }

        # Render minimap column for this row
        push @_out, $class->_render_minimap_column($minimap_data, $screen_row, $theme)
            if $minimap_width > 0;

        push @_out, CLEAR_LINE;
        push @_out, RESET;
        push @text_rows, join('', @_out);
    }

    # Count total spacer rows in visible entries for minimap visibility
    my $total_spacer_rows = 0;
    for my $entry (@entries) {
        $total_spacer_rows++ if $entry && ($entry->{type} // '') eq 'image_spacer';
    }

    return (\@text_rows, \@image_placements, $cursor_image_offset, $total_spacer_rows);
}

# =============================================================================
# Minimap / scrollbar column rendering
# =============================================================================

# Render one row of the minimap column.
# Returns ANSI string for: separator │ + VCS indicator + braille text density
sub _render_minimap_column {
    my ($class, $minimap_data, $screen_row, $theme) = @_;

    my @_out;
    my $minimap_bg = $theme->color('minimap_bg');

    # Separator column (thin vertical line)
    push @_out, $minimap_bg . $theme->color('minimap_separator') . Zepto::Chars->get('minimap_sep');

    # Check if this row has minimap data
    my $row_data;
    if ($minimap_data && $screen_row < $minimap_data->{total_rows}) {
        $row_data = $minimap_data->{rows}[$screen_row];
    }

    # VCS indicator column — use a small dot to match the minimap's compact scale
    if ($row_data && $row_data->{vcs}) {
        my $vcs_status = $row_data->{vcs};
        my $vcs_color = $theme->color("vcs_$vcs_status") // '';
        push @_out, $minimap_bg . $vcs_color . Zepto::Chars->get('minimap_vcs');
    } else {
        push @_out, $minimap_bg . ' ';
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
        push @_out, $text_bg . $text_fg . $row_data->{braille};
    } else {
        # Empty row (beyond document content)
        push @_out, $text_bg . (' ' x $text_cols);
    }

    return join('', @_out);
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

        my @_out = (_move_to($screen_row, 1));
        push @_out, $class->_render_tree_node_content(
            $sticky, $content_width, $theme, 0, 1, $focused,
            $has_scrollbar, $row_idx, $sb, undef, []
        );
        # Border
        push @_out, $border_fg . $tree_bg . $border_char;
        push @tree_rows, join('', @_out);
        $row_idx++;
    }

    # Render tree content rows
    my $sticky_count = $row_idx;  # rows consumed by stickies + filter
    my $available = $height - $sticky_count;

    for my $i (0 .. $available - 1) {
        last if $row_idx >= $height;
        my $flat_idx = $scroll + $i;
        my $screen_row = $row_idx + 1;

        my @_out = (_move_to($screen_row, 1));

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

            my $hover_tree_row = $ui->{hover_tree_row};
            my $is_tree_hover = defined $hover_tree_row && $hover_tree_row == $row_idx
                && !$is_cursor;

            push @_out, $class->_render_tree_node_content(
                $node, $content_width, $theme, $is_cursor, 0, $focused,
                $has_scrollbar, $row_idx, $sb, $node_is_last, \@guides_for_node,
                $filter_active, $is_current, $is_tree_hover
            );

            # Update guide state after rendering this node
            for my $l ($d .. $#guide_active) { $guide_active[$l] = 0; }
            $guide_active[$d] = $node_is_last ? 0 : 1;
        } else {
            # Empty row
            push @_out, $tree_bg . (' ' x $content_width);
            if ($has_scrollbar) {
                push @_out, $tree_bg . ' ';
            }
        }

        # Border
        push @_out, $border_fg . $tree_bg . $border_char;
        push @tree_rows, join('', @_out);
        $row_idx++;
    }

    return \@tree_rows;
}

sub _render_tree_node_content {
    my ($class, $node, $width, $theme, $is_cursor, $is_sticky, $focused,
        $has_scrollbar, $row_idx, $sb, $is_last, $guides, $filter_active,
        $is_current, $is_hover) = @_;

    my @_out;

    # Choose background/foreground
    my ($bg, $fg);
    if ($is_sticky) {
        $bg = $theme->color('tree_sticky_bg');
        $fg = $theme->color('tree_sticky_fg');
    } elsif ($is_cursor) {
        $bg = $theme->color('tree_cursor_bg');
        $fg = $theme->color('tree_cursor_fg');
    } elsif ($is_hover && !$is_current) {
        $bg = $theme->color('tree_hover_bg');
        $fg = $theme->color('tree_hover_fg');
    } elsif ($is_current) {
        $bg = $theme->color('tree_current_bg') // ($focused ? $theme->color('tree_focused_bg') : $theme->color('tree_bg'));
        $fg = $theme->color('tree_current_fg') // $theme->color('tree_fg');
    } else {
        $bg = $focused ? $theme->color('tree_focused_bg') : $theme->color('tree_bg');
        $fg = $theme->color('tree_fg');
    }

    push @_out, $bg;

    # --- Flat filter mode: skip indent/icon, render full path with match highlight ---
    # Only use flat rendering when there's an actual query producing flat results;
    # empty query with filter_active still shows the normal hierarchical tree.
    if ($filter_active && !$node->{is_dir} && $node->{depth} == 0 && $node->{_filter_match_positions}) {
        my $path = $node->{name} // '';  # In flat mode, name == full path
        my $used = 1;  # leading space
        push @_out, ' ';

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
        push @_out, $name_fg . $bg . "$icon ";
        $used += 2;  # icon + space

        my $name_space = $width - $used;

        # Truncate from the LEFT so filename stays visible: …eep/path/file.pm
        # _ellipsis() also returns the trim offset so match-highlight
        # positions (computed against the original $path) can be remapped
        # onto the truncated $display_path below.
        my $display_path = $path;
        my $trim_offset = 0;  # how many chars trimmed from the left
        if ($name_space > 0) {
            ($display_path, $trim_offset) = _ellipsis($path, $name_space, 'start');
        } else {
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
                push @_out, $match_fg . $bg . $ch;
            } else {
                push @_out, $base_fg . $bg . $ch;
            }
        }

        # Pad remainder
        my $pad = $width - $used - length($display_path);
        push @_out, $bg . (' ' x $pad) if $pad > 0;

        # Reset bold/attributes before scrollbar and border
        push @_out, RESET if $is_current;

        # Scrollbar column
        if ($has_scrollbar) {
            my $sb_bg = $theme->color('tree_scrollbar_bg');
            if ($row_idx >= $sb->{thumb_start} && $row_idx <= $sb->{thumb_end}) {
                push @_out, $theme->color('tree_scrollbar_fg') . $sb_bg . "\x{2588}";
            } else {
                push @_out, $sb_bg . ' ';
            }
        }

        return join('', @_out);
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
    push @_out, ' ';
    my $used = 1;

    if ($depth == 0) {
        # Depth 0: arrow + space (dirs) or 2 spaces (files)
        if ($node->{is_dir}) {
            my $arrow_fg = $is_cursor ? $fg : $theme->color('tree_dir_fg');
            my $arrow = $node->{expanded} ? $ch_arrow_d : $ch_arrow_r;
            push @_out, $arrow_fg . $bg . $arrow . ' ';
        } else {
            push @_out, $bg . '  ';
        }
        $used += 2;
    } elsif ($is_sticky) {
        # Sticky headers: indented to match original depth (spaces, no guide lines)
        my $indent_chars = 2 * $depth + 1;  # spaces before arrow/dash
        push @_out, $bg . (' ' x $indent_chars);
        $used += $indent_chars;
        # Arrow for dirs
        if ($node->{is_dir}) {
            my $arrow_fg = $is_cursor ? $fg : $theme->color('tree_sticky_fg');
            my $arrow = $node->{expanded} ? $ch_arrow_d : $ch_arrow_r;
            push @_out, $arrow_fg . $bg . $arrow;
        } else {
            push @_out, $ch_dash;
        }
        $used += 1;
    } else {
        # Depth > 0: indent zone with guides aligned under parent folder icons,
        # then connector, then dash (files) or arrow (dirs).
        #
        # Guide char for ancestor level k sits at column 4+2*k, which is the
        # icon column of the depth-k directory ancestor.  The connector char
        # (├ or ╰) sits at column 2+2*depth (= icon column of the parent dir).
        push @_out, $indent_fg . $bg;

        my $connector_col = 2 + 2 * $depth;
        for my $col (2 .. $connector_col - 1) {
            if ($col >= 4 && ($col - 4) % 2 == 0) {
                my $guide_level = ($col - 4) / 2;
                if ($guides && $guide_level < scalar @$guides && $guides->[$guide_level]) {
                    push @_out, $ch_vertical;
                } else {
                    push @_out, ' ';
                }
            } else {
                push @_out, ' ';
            }
        }
        $used += $connector_col - 2;

        if ($node->{is_dir}) {
            # Dirs: arrow replaces connector for a cleaner look
            my $arrow_fg = $is_cursor ? $fg : $theme->color('tree_dir_fg');
            my $arrow = $node->{expanded} ? $ch_arrow_d : $ch_arrow_r;
            push @_out, $arrow_fg . $bg . $arrow . ' ';
        } else {
            # Files: connector (├ or ╰) + dash
            if ($is_last) {
                push @_out, $ch_last;
            } else {
                push @_out, $ch_branch;
            }
            push @_out, $ch_dash;
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
            $name = _ellipsis($name, $name_space);
        }
    } else {
        $name = '';
    }

    # Render icon
    if ($node->{is_dir}) {
        push @_out, $theme->color('tree_dir_fg') . $bg . $icon_str;
    } else {
        push @_out, $name_fg . $bg . $icon_str;
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
                push @_out, $match_fg . $bg . substr($name, $ci, 1);
            } else {
                push @_out, $name_fg . $bg . substr($name, $ci, 1);
            }
        }
    } else {
        push @_out, $name_fg . $bg . $name;
    }

    # Pad remainder
    my $total_used = $used + length($name);
    my $pad = $width - $total_used;
    push @_out, $bg . (' ' x $pad) if $pad > 0;

    # Reset bold/attributes before scrollbar and border
    push @_out, RESET if $is_current;

    # Scrollbar column
    if ($has_scrollbar) {
        my $sb_bg = $theme->color('tree_scrollbar_bg');
        if ($row_idx >= $sb->{thumb_start} && $row_idx <= $sb->{thumb_end}) {
            push @_out, $theme->color('tree_scrollbar_fg') . $sb_bg . "\x{2588}";  # █
        } else {
            push @_out, $sb_bg . ' ';
        }
    }

    return join('', @_out);
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

    my @_out;
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
        push @_out, $gutter_bg . $vcs_color . Zepto::Chars->get('vcs_expanded');
        push @_out, $gutter_bg . ' ' x ($gutter_width - 1);
    } else {
        my $vcs_char = Zepto::Chars->get('vcs_expanded');  # Fat block for expanded lines
        push @_out, $gutter_bg . $vcs_color . $vcs_char;
        # Blank padding for the rest of the gutter
        push @_out, $gutter_bg . ' ' x ($gutter_width - 1);
    }

    # Line content from base
    my $line_bg = $theme->color('diff_old_bg');
    my $fg = $theme->color('fg');
    push @_out, $line_bg . $fg;

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
            push @_out, ATTR_RESET . $bg . $char_fg;
            $last_bg = $bg;
            $last_fg = $char_fg;
        }
        push @_out, $char;
    }

    # Fill rest with red background (use display width for correct padding)
    my $fill_cols = $width - $old_content_display_width;
    push @_out, $line_bg . (' ' x $fill_cols) if $fill_cols > 0;

    return join('', @_out);
}

# Render a line with selection, syntax, match, and crosshair highlighting
# $content: tab-expanded content for this line
# $orig_content: original content (with tabs) for position conversion
# $cursor_col: visual cursor column (already converted)
# $matches: array of {start, end, is_current} for find matches on this line
sub _render_line_with_highlights {
    my ($class, $content, $line_num, $scroll_col, $width, $view, $theme, $cursor_line, $cursor_col, $is_cursor_line, $tokens, $orig_content, $matches, $diff_mode, $char_highlight, $capture_regions, $is_wrap_cont) = @_;

    my @_out;
    my $len = length($content);

    # Background colors — use diff background when in expanded hunk
    my $is_hunk_line = ($diff_mode && $diff_mode eq 'new') ? 1 : 0;
    my $bg = _resolve_line_bg($theme, 0, $is_hunk_line);

    # Char-level highlight range for stronger green background on changed chars
    my $diff_hl_bg;
    my ($vis_hl_start, $vis_hl_end) = (-1, -1);
    if ($char_highlight && $diff_mode && $diff_mode eq 'new') {
        $diff_hl_bg = $theme->color('diff_new_highlight_bg');
        $vis_hl_start = $char_highlight->[0] - $scroll_col;
        $vis_hl_end = $char_highlight->[1] - $scroll_col;
    }
    my $line_bg = _resolve_line_bg($theme, 1, $is_hunk_line);
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

    # Build multi-cursor selection ranges for this line
    my @multi_cursor_sel;  # column → 1 if inside a multi-cursor selection
    my @multi_cursor_pos;  # column → 1 if a multi-cursor is at this position
    if ($view->has_multi_cursors()) {
        for my $mc (@{$view->multi_cursors()}) {
            # Check if this cursor is on this line
            if ($mc->{line} == $line_num) {
                my $vcol = _char_to_visual_col($orig_content, $mc->{col}) - $scroll_col;
                $multi_cursor_pos[$vcol] = 1 if $vcol >= 0 && $vcol < $len;
            }
            # Check if this cursor has a selection that covers this line
            if (defined $mc->{anchor_line}) {
                my ($msl, $msc, $mel, $mec);
                if ($mc->{anchor_line} > $mc->{line}
                    || ($mc->{anchor_line} == $mc->{line} && $mc->{anchor_col} > $mc->{col})) {
                    ($msl, $msc, $mel, $mec) = ($mc->{line}, $mc->{col}, $mc->{anchor_line}, $mc->{anchor_col});
                } else {
                    ($msl, $msc, $mel, $mec) = ($mc->{anchor_line}, $mc->{anchor_col}, $mc->{line}, $mc->{col});
                }
                if ($line_num >= $msl && $line_num <= $mel) {
                    my $ms = 0;
                    my $me = $len;
                    $ms = _char_to_visual_col($orig_content, $msc) - $scroll_col if $line_num == $msl;
                    $me = _char_to_visual_col($orig_content, $mec) - $scroll_col if $line_num == $mel;
                    $ms = 0 if $ms < 0;
                    $me = $len if $me > $len;
                    for my $c ($ms .. $me - 1) {
                        $multi_cursor_sel[$c] = 1 if $c >= 0 && $c < $len;
                    }
                }
            }
        }
    }

    # Render character by character with appropriate backgrounds and foregrounds
    # Priority: current_match > other_match > multi_cursor_sel > selection > cursor_line/col > syntax > default
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
        # Check if in a multi-cursor selection (secondary cursor highlights)
        elsif ($multi_cursor_sel[$i]) {
            $char_bg = $sel_bg_color;
            $char_fg = $syntax_fg[$i] // $fg;
            $style_key = "mcsel:" . ($syntax_fg[$i] // 'def');
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
            push @_out, ATTR_RESET . $char_bg . $char_fg;
            $last_style = $style_key;
        }

        push @_out, $char;
    }

    return join('', @_out);
}

# Render the status bar with Nerd Font segments
sub _render_status_bar {
    my ($class, $doc, $view, $theme, $cols, $message, $status_hint, $hint_color) = @_;

    my @_out;
    my $ar = Zepto::Chars->get('arrow_right');

    # If there's a message, show it simply
    if ($message) {
        # Truncate from the start (keep the tail — e.g. filename — visible)
        # so a long message (e.g. "Saved: /very/long/path...") never
        # overflows past $cols. An untruncated message longer than the
        # terminal width wraps onto the next real terminal row, scrolling
        # the whole screen and corrupting everything above the status bar.
        my $max_msg_width = $cols - 1;
        $message = _ellipsis($message, $max_msg_width, 'start') if $max_msg_width > 0;
        push @_out, $theme->color('status_bg') . $theme->color('warning_fg');
        push @_out, ' ' . $message;
        my $padding = $cols - length($message) - 1;
        push @_out, ' ' x $padding if $padding > 0;
        push @_out, CLEAR_LINE . RESET;
        return join('', @_out);
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
    push @_out, $theme->color('status_file_bg') . $theme->color('status_file_fg');
    push @_out, " $display_path";
    if ($is_dirty) {
        push @_out, $theme->color('status_modified_fg');
        push @_out, " " . Zepto::Chars->get('modified');
        push @_out, $theme->color('status_file_fg');
    }
    push @_out, ' ';

    # Read-only indicator for binary files
    my $ro_text = '';
    my $ro_width = 0;
    if ($doc && $doc->{_is_binary}) {
        $ro_text = ' READ ONLY ';
        $ro_width = length($ro_text);
        $ro_width += $segment_overhead;  # Arrow char
    }

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

    # Arrow transition: file -> read-only indicator / column indicator / middle
    my $prev_edge_color = 'status_file_edge';
    if (Zepto::Chars->enabled()) {
        if ($ro_width > 0) {
            # file -> read-only indicator
            push @_out, $theme->color('column_indicator_bg') . $theme->color($prev_edge_color);
            push @_out, $ar;
            push @_out, $theme->color('warning_fg') . $ro_text;
            $prev_edge_color = 'column_indicator_edge';
        }
        if ($col_width > 0) {
            # prev -> column indicator
            push @_out, $theme->color('column_indicator_bg') . $theme->color($prev_edge_color);
            push @_out, $ar unless $ro_width > 0;  # Arrow already drawn if no RO segment
            push @_out, $theme->color('column_indicator_fg') . $col_text;
            $prev_edge_color = 'column_indicator_edge';
        }
        # final -> middle
        push @_out, $theme->color('status_bg') . $theme->color($prev_edge_color);
        push @_out, $ar;
    } else {
        if ($ro_width > 0) {
            push @_out, $theme->color('column_indicator_bg') . $theme->color('warning_fg');
            push @_out, $ro_text;
        }
        if ($col_width > 0) {
            push @_out, $theme->color('column_indicator_bg') . $theme->color('column_indicator_fg');
            push @_out, $col_text;
        }
    }

    # Middle fill (account for indicator widths)
    my $middle = $cols - $file_width - $segment_overhead - $ro_width - $col_width - $hint_width;
    $middle = 0 if $middle < 0;
    push @_out, $theme->color('status_bg') . $theme->color('status_fg');
    push @_out, ' ' x $middle if $middle > 0;

    # Hint (right-aligned, colored by hunk type)
    if ($hint_width > 0) {
        push @_out, $theme->color('status_bg');
        push @_out, $hint_color // $theme->color('gutter_fg');
        push @_out, $hint_text;
    }

    push @_out, CLEAR_LINE;
    push @_out, RESET;

    return join('', @_out);
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

# =============================================================================
# Modifier-Grouped Pill Columns (⌃ left / ⌥ right — see UI_GUIDELINES.md)
# =============================================================================
#
# Build the "core navigation" hint text (close tab / switch tabs / quit) —
# shared between the DOCUMENT-context tab bar corner hint
# (_render_tab_bar) and the FILE_TREE-context hint row
# (_render_context_status_bar) so both contexts render identical wording
# from one source instead of two copies that can silently drift out of
# sync (see bugs.md "Discoverability Contract gaps" — this exact
# diverging-sources-of-truth problem is what caused the original
# DOCUMENT-context Quit gap; don't recreate it here).
#
# Two-tier degradation, mirroring _fit_pill_group's idiom: try the labeled
# form first (plain-language words next to the glyphs — a bare glyph
# cluster like "⌃W ×  ⌥, ←  ⌥. →" was flagged by an LLM-vision
# discoverability sweep as unlabeled/ambiguous to a first-time user); fall
# back to the compact glyphs-only form when there isn't room for labels;
# return undef when nothing fits so the caller can degrade to a blank fill
# instead of truncating mid-glyph.
#
# $available is the FULL width budget, including the one-space padding the
# caller renders on each side of the returned text (matches the historical
# accounting in _render_tab_bar, where "remaining" already included that
# padding) — callers must not add the padding on top of what they pass in.
sub _core_nav_hint_text {
    my ($available) = @_;

    my $hint_close_lbl = CTRL_GLYPH . "W close";                    # ⌃W close
    my $hint_nav_lbl   = "\x{2325}\x{2190}/\x{2192} tabs";           # ⌥←/→ tabs
    my $hint_quit_lbl  = CTRL_GLYPH . "Q quit";                     # ⌃Q quit
    my $hint_labeled   = "$hint_close_lbl   $hint_nav_lbl   $hint_quit_lbl";

    my $hint_close_compact = CTRL_GLYPH . "W \x{00d7}";                    # ⌃W ×
    my $hint_nav_compact   = "\x{2325}, \x{2190} \x{2325}. \x{2192}";       # ⌥, ← ⌥. →
    my $hint_quit_compact  = CTRL_GLYPH . "Q";                              # ⌃Q
    my $hint_compact = "$hint_close_compact $hint_nav_compact $hint_quit_compact";

    my $labeled_width = length($hint_labeled) + 2;  # +2 for surrounding spaces
    my $compact_width = length($hint_compact) + 2;

    return $hint_labeled if $available >= $labeled_width;
    return $hint_compact if $available >= $compact_width;
    return undef;
}

# Greedily fit as many candidate pills (sorted ascending by priority, i.e.
# highest-importance first) into $budget columns. Tries the full pill form
# (icon + label + key) first; if even the highest-priority candidate can't
# fit in full form, the whole group falls back to a compact form (icon +
# key, no label) and retries. This guarantees the top-priority pill in a
# group renders in *some* form whenever the group has any budget at all,
# instead of just vanishing once the label makes it too wide.
#
# Returns (\@fit_pills, $used_width) where each fit pill is a shallow copy
# of the candidate with `text` and `width` set to whichever form was used.
sub _fit_pill_group {
    my ($candidates, $budget, $nerd_font) = @_;
    return ([], 0) if $budget <= 0 || !@$candidates;

    my $try_mode = sub {
        my ($mode) = @_;
        my @fit;
        my $used = 0;
        for my $c (@$candidates) {
            my $w  = $mode eq 'full' ? $c->{full_width} : $c->{compact_width};
            my $pw = $w + ($nerd_font ? 3 : 1);  # caps (2) + gap (1), or just gap
            last if $used + $pw > $budget;
            push @fit, { %$c, text => ($mode eq 'full' ? $c->{full_text} : $c->{compact_text}), width => $w };
            $used += $pw;
        }
        return (\@fit, $used);
    };

    my ($full_fit, $full_used) = $try_mode->('full');
    return ($full_fit, $full_used) if @$full_fit;

    return $try_mode->('compact');
}

# Render a non-interactive modifier group label (e.g. " ⌃ ") — a Separator,
# not a pill: no rounded caps, dim text, not clickable. Mutates $center_col_ref.
sub _render_group_label {
    my ($class, $theme, $sym, $out_ref, $center_col_ref) = @_;
    push @$out_ref, $theme->color('status_bg') . $theme->color('gutter_fg');
    push @$out_ref, " $sym ";
    $$center_col_ref += 3;
}

# Render a list of already-fit pills (from _fit_pill_group) with rounded
# caps, hover highlighting, and click button registration. Mutates
# $out_ref, $buttons_ref, $center_col_ref, and $btn_offset_ref (so the
# caller can chain multiple groups and keep hover indices contiguous with
# render order — see Editor::_handle_mouse_hover / get_status_buttons).
sub _render_pill_list {
    my ($class, $theme, $nerd_font, $round_l, $round_r, $fit_list,
        $hover_pill_index, $btn_offset_ref, $out_ref, $buttons_ref, $center_col_ref) = @_;

    for my $i (0 .. $#$fit_list) {
        my $pill = $fit_list->[$i];
        my $btn_idx  = $$btn_offset_ref + $i;
        my $is_hover = defined $hover_pill_index && $hover_pill_index == $btn_idx;
        my $eff_fg   = $is_hover ? 'pill_hover_fg'   : $pill->{fg};
        my $eff_bg   = $is_hover ? 'pill_hover_bg'   : $pill->{bg};
        my $eff_edge = $is_hover ? 'pill_hover_edge' : $pill->{edge};

        if ($nerd_font) {
            push @$out_ref, $theme->color('status_bg') . $theme->color($eff_edge);
            push @$out_ref, $round_l;
            $$center_col_ref += 1;
        }

        push @$out_ref, $theme->color($eff_bg) . $theme->color($eff_fg);
        push @$out_ref, " $pill->{text} ";
        push @$buttons_ref, {
            x_start    => $$center_col_ref,
            x_end      => $$center_col_ref + $pill->{width} - 1,
            command_id => $pill->{cmd}{id},
        };
        $$center_col_ref += $pill->{width};

        if ($nerd_font) {
            push @$out_ref, $theme->color('status_bg') . $theme->color($eff_edge);
            push @$out_ref, $round_r;
            $$center_col_ref += 1;
        }

        push @$out_ref, $theme->color('status_bg') . ' ';
        $$center_col_ref += 1;
    }

    $$btn_offset_ref += scalar @$fit_list;
}

sub _render_context_status_bar {
    my ($class, $doc, $view, $theme, $cols, $message, $message_is_error, $ui, $word_wrap_active) = @_;

    my @_out;
    my @buttons;
    my $ar = Zepto::Chars->get('arrow_right');
    my $nerd_font = Zepto::Chars->enabled();

    # If there's a message, show it simply
    if ($message) {
        # Truncate from the start (keep the tail — e.g. filename — visible)
        # so a long message (e.g. "Saved: /very/long/path...") never
        # overflows past $cols. An untruncated message longer than the
        # terminal width wraps onto the next real terminal row, scrolling
        # the whole screen and corrupting everything above the status bar.
        my $max_msg_width = $cols - 1;
        $message = _ellipsis($message, $max_msg_width, 'start') if $max_msg_width > 0;
        my $fg = $message_is_error ? $theme->color('error_fg') : $theme->color('warning_fg');
        push @_out, $theme->color('status_bg') . $fg;
        push @_out, ' ' . $message;
        my $padding = $cols - length($message) - 1;
        push @_out, ' ' x $padding if $padding > 0;
        push @_out, CLEAR_LINE . RESET;
        $class->_set_status_buttons([]);
        return join('', @_out);
    }

    # Tree-focused: show simplified hint bar
    my $tree = $ui->{file_tree};
    if ($tree && $tree->focused()) {
        my $cursor_icon = Zepto::Chars->get('cursor_pos');
        my $node = $tree->cursor_node();
        my $node_path = $node ? $node->{path} : '';

        my $round_l = Zepto::Chars->get('round_left');
        my $round_r = Zepto::Chars->get('round_right');

        # Right: Open File + palette trigger pills. Computed BEFORE the
        # left breadcrumb so the breadcrumb can be bounded against the
        # width these two fixed, never-dropped pills actually need — see
        # bugs.md "FILE_TREE breadcrumb + Open + Commands can overflow the
        # terminal width" for the incident this guards against (an
        # unbounded tree cursor path, e.g. several nested directories deep,
        # pushed the whole row past $cols and the terminal soft-wrapped the
        # overflow, scrolling the tab bar/ruler out of view).
        my $open_icon = Zepto::Chars->get('folder_open');
        my $open_text = " $open_icon Open " . CTRL_GLYPH . "O ";
        my $open_width = length($open_text) + ($nerd_font ? 2 : 0);

        my $palette_icon = Zepto::Chars->get('palette');
        my $palette_text = " $palette_icon Commands " . CTRL_GLYPH . "\x{2423} ";  # ⌃␣
        my $palette_width = length($palette_text) + ($nerd_font ? 2 : 0);

        my $right_width = $open_width + 1 + $palette_width;  # +1 for gap

        # Bound the breadcrumb to whatever's left after the fixed right
        # pills (plus the icon+spaces overhead and the nerd-font edge cap),
        # never letting it alone push the row past $cols. Ellipsize from
        # the start so the tail (the file/dir's own name, the most useful
        # part of a nested path) stays visible; if there's no room at all,
        # drop it to an empty string rather than emitting a negative-width
        # substr or overflowing — degrades honestly like every other hint
        # in this row, never garbles the line.
        my $left_fixed_overhead = length(" $cursor_icon  ") + ($nerd_font ? 1 : 0);
        my $max_path_width = $cols - $left_fixed_overhead - $right_width;
        if ($max_path_width < 1) {
            $node_path = '';
        } elsif (length($node_path) > $max_path_width) {
            $node_path = _ellipsis($node_path, $max_path_width, 'start');
        }

        push @_out, $theme->color('status_file_bg') . $theme->color('status_file_fg');
        my $left_text = " $cursor_icon $node_path ";
        push @_out, $left_text;
        my $left_width = length($left_text);

        if ($nerd_font) {
            my $tree_round_r = Zepto::Chars->get('round_right');
            push @_out, $theme->color('status_bg') . $theme->color('status_file_edge');
            push @_out, $tree_round_r;
            $left_width += 1;
        }

        # Middle: tree-context hint pills. Ordered highest-priority first
        # (see docs/UI_GUIDELINES.md "Discoverability Contract"):
        #
        #   1. ⌃B back — the way to switch focus back to the editor
        #      (keeping the tree open) without dismissing it. Previously
        #      there was NO on-screen hint for this anywhere in the
        #      FILE_TREE context — see bugs.md "FILE_TREE context is
        #      missing on-screen hints... switching focus back to the
        #      editor" (P1, confirmed by both the automated LLM vision-judge
        #      sweep and manual testing). This is the single most important
        #      addition here, so it goes first.
        #   2. ↵ open — opening the highlighted file (arrow-key navigation
        #      already previews/opens files, so this is a close second, not
        #      a first-time-blocking gap the way #1 was).
        #   3. ↑↓ / ←→ fold — navigation basics a user is more likely to
        #      already know or find via ⌃␣ Commands (the always-visible
        #      fallback pill on the right), so these drop first.
        #
        # Width-fitting reuses _fit_pill_group (shared with the DOCUMENT
        # status bar's ⌃/⌥ pill columns) instead of a hand-rolled
        # last-item-wins loop: it guarantees the top-priority pill (⌃B back)
        # renders in *some* form — full or compact — whenever there's any
        # budget at all, rather than vanishing outright just because its
        # full label didn't quite fit.
        my $nav_icon = Zepto::Chars->get('cursor_pos');
        my @tree_pill_candidates = (
            { full_text => CTRL_GLYPH . "B back",  compact_text => CTRL_GLYPH . "B",
              fg => 'pill_action_fg', bg => 'pill_action_bg', edge => 'pill_action_edge' },
            { full_text => "\x{21B5} open",   compact_text => "\x{21B5}",
              fg => 'pill_action_fg', bg => 'pill_action_bg', edge => 'pill_action_edge' },
            { full_text => "$nav_icon \x{2191}\x{2193}", compact_text => "\x{2191}\x{2193}",
              fg => 'pill_action_fg', bg => 'pill_action_bg', edge => 'pill_action_edge' },
            { full_text => "\x{2190}\x{2192} fold", compact_text => "\x{2190}\x{2192}",
              fg => 'pill_action_fg', bg => 'pill_action_bg', edge => 'pill_action_edge' },
        );
        $_->{full_width}    = length($_->{full_text}) + 2    for @tree_pill_candidates;
        $_->{compact_width} = length($_->{compact_text}) + 2 for @tree_pill_candidates;

        my $available = $cols - $left_width - $right_width;
        $available = 0 if $available < 0;
        my $center_col = $left_width + 1;

        my ($fit_tree_pills, undef) = _fit_pill_group(\@tree_pill_candidates, $available, $nerd_font);

        for my $pill (@$fit_tree_pills) {
            if ($nerd_font) {
                push @_out, $theme->color('status_bg') . $theme->color($pill->{edge});
                push @_out, $round_l;
                $center_col += 1;
            }
            push @_out, $theme->color($pill->{bg}) . $theme->color($pill->{fg});
            push @_out, " $pill->{text} ";
            $center_col += length($pill->{text}) + 2;
            if ($nerd_font) {
                push @_out, $theme->color('status_bg') . $theme->color($pill->{edge});
                push @_out, $round_r;
                $center_col += 1;
            }
            push @_out, $theme->color('status_bg') . ' ';
            $center_col += 1;
        }

        # Fill remaining space, with the same core-nav hint (close tab /
        # switch tabs / quit) the DOCUMENT-context tab bar shows, if there's
        # still room after the tree-specific pills above. Lowest priority
        # of everything in this row — a user already knows how to quit or
        # switch tabs, or can find it via ⌃␣ Commands, so this is the first
        # thing to drop under width pressure; dropping it never removes the
        # only hint for a feature the way the FILE_TREE gap this fix
        # addresses did, since quit/tab-nav still have their DOCUMENT-context
        # hint and the palette fallback. Shares _core_nav_hint_text() with
        # _render_tab_bar so wording can't drift between the two contexts.
        my $remaining = $cols - $center_col - $right_width + 1;
        $remaining = 0 if $remaining < 0;
        my $nav_hint = _core_nav_hint_text($remaining);

        push @_out, $theme->color('status_bg');
        if (defined $nav_hint) {
            my $hint_width = length($nav_hint) + 2;
            my $fill = $remaining - $hint_width;
            push @_out, ' ' x $fill if $fill > 0;
            push @_out, ' ' . $theme->color('tab_shortcut_fg') . $nav_hint . $theme->color('status_bg') . ' ';
        } elsif ($remaining > 0) {
            push @_out, ' ' x $remaining;
        }

        # Open File pill
        if ($nerd_font) {
            push @_out, $theme->color('status_bg') . $theme->color('pill_palette_edge');
            push @_out, $round_l;
        }
        push @_out, $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
        push @_out, $open_text;
        if ($nerd_font) {
            push @_out, $theme->color('status_bg') . $theme->color('pill_palette_edge');
            push @_out, $round_r;
        }
        push @buttons, {
            x_start    => $cols - $right_width + 1,
            x_end      => $cols - $right_width + $open_width,
            command_id => 'open_file',
        };

        push @_out, $theme->color('status_bg') . ' ';  # gap between pills

        # Palette trigger with rounded caps
        if ($nerd_font) {
            push @_out, $theme->color('status_bg') . $theme->color('pill_palette_edge');
            push @_out, $round_l;
            push @_out, $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
            push @_out, $palette_text;
            push @_out, $theme->color('status_bg') . $theme->color('pill_palette_edge');
            push @_out, $round_r;
        } else {
            push @_out, $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
            push @_out, $palette_text;
        }
        push @buttons, {
            x_start    => $cols - $palette_width + 1,
            x_end      => $cols,
            command_id => 'open_palette',
        };

        push @_out, CLEAR_LINE . RESET;
        $class->_set_status_buttons(\@buttons);
        return join('', @_out);
    }

    # === Document context: build pill-based status bar ===

    # RIGHT: Palette trigger pill (always visible, rightmost — see
    # UI_GUIDELINES.md "Context-Aware Status Bar"). Open File used to be a
    # second hardcoded pill here; it's now an ordinary ⌃ group candidate
    # (⌃O/⌃P) like every other Ctrl shortcut, so it can drop at very narrow
    # widths just like the rest of that column.
    #
    # Computed FIRST (before the left segment) because it has fixed width
    # and never shrinks — everything else on this line has to be bounded
    # against it, not the other way around. See QA-REG-179 / bugs.md: this
    # bar used to build the left (cursor/COL/multi-cursor) segment and emit
    # it unconditionally, then only *reduce* the center ⌃/⌥ pill groups to
    # fit — with nothing left to shrink, a wide left segment plus this fixed
    # palette pill could together exceed $cols, and the terminal would
    # soft-wrap the overflow onto a phantom row, scrolling and corrupting
    # the whole screen. Computing the reservation up front lets the left
    # segment (below) check its own budget before emitting anything.
    my $palette_icon = Zepto::Chars->get('palette');
    my $palette_text = " $palette_icon Commands " . CTRL_GLYPH . "\x{2423} ";
    my $palette_text_width = length($palette_text);
    # Total palette width includes the round caps (left + right)
    my $palette_total_width = $palette_text_width + ($nerd_font ? 2 : 0);
    my $nerd_cap = $nerd_font ? 1 : 0;  # round_r cap closing the left segment

    # 1. LEFT: Cursor position pill with ⌃G shortcut (always visible, fixed width)
    my $cursor_icon = Zepto::Chars->get('cursor_pos');
    my $goto_shortcut = CTRL_GLYPH . "G";
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

    # Hard floor: cursor pill + round cap + gap + palette pill + gap must
    # never exceed $cols, even in pathological cases (huge line/col numbers
    # on a giant file, or a very long single line pushing the column number
    # into the thousands). Ellipsize the cursor pill's own text if it alone
    # would blow the budget — same backstop already used for transient
    # messages above (_ellipsis). No-op in the overwhelming common case.
    my $cursor_budget = $cols - 2 - $nerd_cap - $palette_total_width - 2;
    $cursor_budget = 1 if $cursor_budget < 1;
    $cursor_text = _ellipsis($cursor_text, $cursor_budget, 'end')
        if length($cursor_text) > $cursor_budget;

    push @_out, $theme->color('status_pos_bg') . $theme->color('status_pos_fg');
    push @_out, " $cursor_text ";
    my $left_width = length($cursor_text) + 2;
    push @buttons, {
        x_start    => 1,
        x_end      => $left_width,
        command_id => 'goto_line',
    };

    # Column mode indicator (inline, if active) — supplementary context,
    # not essential. Drop it rather than let it push the bar past $cols;
    # the cursor pill and palette pill always win. See QA-REG-179.
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
        my $col_seg_width = length($col_text) + 2;
        if ($left_width + $col_seg_width + $nerd_cap + $palette_total_width + 2 <= $cols) {
            push @_out, $theme->color('column_indicator_bg') . $theme->color('column_indicator_fg');
            push @_out, " $col_text ";
            $left_width += $col_seg_width;
        }
    }

    # Multi-cursor indicator — same optional-drop treatment as COL above.
    # This is the segment that actually overflowed in the confirmed repro:
    # ⌃D ("select next occurrence") a handful of times grows "N cursors"
    # past the point where the left segment + palette pill still fit in a
    # 40-column terminal. See QA-REG-179.
    if ($view && $view->has_multi_cursors()) {
        my $mc_count = $view->cursor_count();
        my $mc_text = "${mc_count} cursors";
        my $mc_seg_width = length($mc_text) + 2;
        if ($left_width + $mc_seg_width + $nerd_cap + $palette_total_width + 2 <= $cols) {
            push @_out, $theme->color('column_indicator_bg') . $theme->color('column_indicator_fg');
            push @_out, " $mc_text ";
            $left_width += $mc_seg_width;
        }
    }

    my $round_l = Zepto::Chars->get('round_left');
    my $round_r = Zepto::Chars->get('round_right');

    if ($nerd_font) {
        push @_out, $theme->color('status_bg') . $theme->color('status_pos_edge');
        push @_out, $round_r;
        $left_width += 1;
    }

    # 3. CENTER: two modifier-grouped pill columns — ⌃ (Ctrl) on the left,
    # ⌥ (Alt) on the right — each showing its modifier glyph once instead
    # of repeating it on every pill. See docs/UI_GUIDELINES.md.
    my $editor = $ui->{editor};
    # -2 accounts for the gap after the cursor pill and the gap before the palette pill
    my $available = $cols - $left_width - $palette_total_width - 2;
    $available = 0 if $available < 0;

    my $ctrl_sym = Zepto::CommandRegistry::SYM_CTRL();
    my $alt_sym  = Zepto::CommandRegistry::SYM_ALT();

    # Collect candidates, sorted by priority (ascending = most important first),
    # split into the ⌃ and ⌥ columns by which modifier their shortcut starts with.
    # Commands with no shortcut, a bare function key, or a multi-modifier chord
    # (e.g. ⌃⇧F) don't belong to either column and are never a status bar pill —
    # they remain reachable from the command palette.
    my (@ctrl_candidates, @alt_candidates);
    if ($editor) {
        my @cmds = Zepto::CommandRegistry->commands_for_status_bar('document', $cols, $editor);
        for my $cmd (@cmds) {
            my $shortcut = $cmd->{shortcut} // '';
            my $group = index($shortcut, $ctrl_sym) == 0 ? 'ctrl'
                      : index($shortcut, $alt_sym)  == 0 ? 'alt'
                      : undef;
            next unless $group;
            my $sym = $group eq 'ctrl' ? $ctrl_sym : $alt_sym;
            (my $stripped = $shortcut) =~ s/\Q$sym\E//g;

            my $icon = Zepto::Chars->get($cmd->{icon} // 'menu');
            # Theme pill: icon reflects the actual current mode (auto/dark/
            # light), not a static moon regardless of state.
            if (($cmd->{pref} // '') eq 'theme') {
                my $theme_state = Zepto::CommandRegistry->get_toggle_state($cmd, $editor) // 'dark';
                $icon = Zepto::Chars->get("theme_$theme_state");
            }
            my ($fg, $bg, $edge, $label, $is_on);

            if ($cmd->{type} eq 'toggle') {
                my $state = Zepto::CommandRegistry->get_toggle_state($cmd, $editor);
                my $state_display = Zepto::CommandRegistry->get_toggle_display($cmd, $editor);

                # Determine effective on/off (handle theme specially)
                $is_on = $state ? 1 : 0;
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

                $label = $cmd->{label};
                if ($state_display ne '' && $state_display ne 'on' && $state_display ne 'off') {
                    $label .= ":$state_display";
                }
            }
            else {
                $label = $cmd->{label};
                $fg = 'pill_action_fg';
                $bg = 'pill_action_bg';
                $edge = 'pill_action_edge';
            }

            my $full_text = $stripped ne '' ? "$icon $label $stripped" : "$icon $label";
            my $compact_text = $stripped ne '' ? "$icon $stripped" : $icon;

            my $entry = {
                cmd           => $cmd,
                fg            => $fg,
                bg            => $bg,
                edge          => $edge,
                priority      => $cmd->{priority},
                is_on         => $is_on,
                full_text     => $full_text,
                full_width    => length($full_text) + 2,
                compact_text  => $compact_text,
                compact_width => length($compact_text) + 2,
            };
            push @{ $group eq 'ctrl' ? \@ctrl_candidates : \@alt_candidates }, $entry;
        }
    }

    # Budget negotiation: figure out the minimum width each column needs to
    # show just its priority-1 pill (label + compact form of the top item).
    # Whenever both minimums fit in the available width, reserve alt's
    # minimum up front so ctrl can never greedily starve it, then hand
    # back whatever ctrl didn't use. This guarantees the priority-1 pill in
    # *each* column renders (full or compact) as long as the terminal has
    # room for both. Under genuine extreme-narrow scarcity (not even both
    # minimums fit), ctrl — rendered first, holds Save — wins the
    # remaining space and alt may drop entirely; see docs/UI_GUIDELINES.md.
    my $ctrl_label_w = @ctrl_candidates ? 3 : 0;  # " ⌃ "
    my $alt_label_w  = @alt_candidates  ? 3 : 0;  # " ⌥ "

    my $ctrl_min = @ctrl_candidates
        ? $ctrl_label_w + $ctrl_candidates[0]{compact_width} + ($nerd_font ? 3 : 1)
        : 0;
    my $alt_min = @alt_candidates
        ? $alt_label_w + $alt_candidates[0]{compact_width} + ($nerd_font ? 3 : 1)
        : 0;

    my $alt_reserve = ($ctrl_min + $alt_min <= $available) ? $alt_min : 0;

    my $ctrl_pill_budget = $available - $alt_reserve - $ctrl_label_w;
    $ctrl_pill_budget = 0 if $ctrl_pill_budget < 0;
    my ($ctrl_fit, $ctrl_pills_used) = _fit_pill_group(\@ctrl_candidates, $ctrl_pill_budget, $nerd_font);
    my $ctrl_total_used = @$ctrl_fit ? ($ctrl_label_w + $ctrl_pills_used) : 0;

    my $alt_pill_budget = $available - $ctrl_total_used - $alt_label_w;
    $alt_pill_budget = 0 if $alt_pill_budget < 0;
    my ($alt_fit, $alt_pills_used) = _fit_pill_group(\@alt_candidates, $alt_pill_budget, $nerd_font);
    my $alt_total_used = @$alt_fit ? ($alt_label_w + $alt_pills_used) : 0;

    # Render: [cursor pill][gap][⌃ group][fill][⌥ group][gap][palette pill]
    my $center_col = $left_width + 1;
    my $hover_pill_index = $ui->{hover_pill_index};
    my $pill_btn_offset = scalar @buttons;

    if (@$ctrl_fit) {
        push @_out, $theme->color('status_bg') . ' ';
        $center_col += 1;
        $class->_render_group_label($theme, $ctrl_sym, \@_out, \$center_col);
        $class->_render_pill_list($theme, $nerd_font, $round_l, $round_r, $ctrl_fit,
            $hover_pill_index, \$pill_btn_offset, \@_out, \@buttons, \$center_col);
    }

    # Middle fill — right-aligns the ⌥ column against the palette pill
    my $tail_width = (@$alt_fit ? $alt_label_w + $alt_pills_used : 0) + $palette_total_width;
    my $remaining = $cols - $center_col - $tail_width - 1;  # -1 for gap before palette pill
    $remaining = 0 if $remaining < 0;
    push @_out, $theme->color('status_bg');
    push @_out, ' ' x $remaining if $remaining > 0;
    $center_col += $remaining;

    if (@$alt_fit) {
        $class->_render_group_label($theme, $alt_sym, \@_out, \$center_col);
        $class->_render_pill_list($theme, $nerd_font, $round_l, $round_r, $alt_fit,
            $hover_pill_index, \$pill_btn_offset, \@_out, \@buttons, \$center_col);
    }

    push @_out, $theme->color('status_bg') . ' ';  # gap between pills

    # Palette trigger pill (rightmost) with rounded caps
    if ($nerd_font) {
        push @_out, $theme->color('status_bg') . $theme->color('pill_palette_edge');
        push @_out, $round_l;
    }
    push @_out, $theme->color('pill_palette_bg') . $theme->color('pill_palette_fg');
    push @_out, $palette_text;
    if ($nerd_font) {
        push @_out, $theme->color('status_bg') . $theme->color('pill_palette_edge');
        push @_out, $round_r;
    }
    push @buttons, {
        x_start    => $cols - $palette_total_width + 1,
        x_end      => $cols,
        command_id => 'open_palette',
    };

    push @_out, CLEAR_LINE . RESET;
    $class->_set_status_buttons(\@buttons);

    return join('', @_out);
}

# Render dialog box
sub _render_dialog {
    my ($class, $theme, $dialog, $total_rows, $total_cols) = @_;

    my @_out;

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
    push @_out, $theme->color('dialog_bg');
    push @_out, $theme->color('dialog_fg');

    # Top border
    push @_out, _move_to($y, $x);
    push @_out, $theme->color('dialog_border');
    push @_out, $box_tl;
    push @_out, $box_h x ($dialog_width - 2);
    push @_out, $box_tr;

    # Title row
    push @_out, _move_to($y + 1, $x);
    push @_out, $theme->color('dialog_bg') . $theme->color('dialog_fg');
    push @_out, $box_v;
    my $title_text = " $title ";
    my $title_pad = $dialog_width - 2 - length($title_text);
    push @_out, $title_text . (' ' x $title_pad);
    push @_out, $box_v;

    # Prompt row
    push @_out, _move_to($y + 2, $x);
    push @_out, $box_v;
    my $prompt_text = " $prompt";
    if (length($prompt_text) > $dialog_width - 4) {
        $prompt_text = substr($prompt_text, 0, $dialog_width - 4);
    }
    push @_out, $prompt_text . (' ' x ($dialog_width - 2 - length($prompt_text)));
    push @_out, $box_v;

    # Input row
    push @_out, _move_to($y + 3, $x);
    push @_out, $box_v . " ";
    push @_out, $theme->color('dialog_input_bg');
    push @_out, $theme->color('dialog_input_fg');

    my $input_width = $dialog_width - 4;
    my $display_value = $value;
    if (length($display_value) > $input_width) {
        $display_value = substr($display_value, length($display_value) - $input_width);
    }
    push @_out, $display_value;
    push @_out, ' ' x ($input_width - length($display_value));

    push @_out, $theme->color('dialog_bg') . $theme->color('dialog_fg');
    push @_out, " " . $box_v;

    # Bottom border
    push @_out, _move_to($y + 4, $x);
    push @_out, $theme->color('dialog_border');
    push @_out, $box_bl;
    push @_out, $box_h x ($dialog_width - 2);
    push @_out, $box_br;

    push @_out, RESET;

    return join('', @_out);
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

    my @_out;
    push @_out, $theme->color('status_bg') . $theme->color('status_fg');

    my $prompt = $input->{prompt} // '';
    my $widget = $input->{widget};
    my $hint   = $input->{hint} // '';
    my $input_id = $input->{id} // '';

    # For goto_line: render as pill-style input with cursor icon
    my $prompt_str;
    if ($input_id eq 'goto_line') {
        my $cursor_icon = Zepto::Chars->get('cursor_pos');
        push @_out, $theme->color('status_pos_bg') . $theme->color('status_pos_fg');
        $prompt_str = " $cursor_icon ";
    } else {
        $prompt_str = ' ' . $prompt . ' ';
    }
    push @_out, $prompt_str;

    # Input field with distinct background
    push @_out, $theme->color('dialog_input_bg');
    push @_out, $theme->color('dialog_input_fg');

    # Calculate width for input field
    my $prompt_len = length($prompt_str);
    my $hint_str = $hint ? ($input_id eq 'goto_line' ? "  $hint" : " ($hint)") : '';
    my $hint_len = length($hint_str);
    my $input_width;
    if ($input->{wide}) {
        # Use most available space for the input field
        $input_width = $cols - $prompt_len - $hint_len - 2;
        $input_width = FOOTER_INPUT_WIDTH_WIDE_MIN if $input_width < FOOTER_INPUT_WIDTH_WIDE_MIN;
    } elsif ($input_id eq 'goto_line') {
        $input_width = FOOTER_INPUT_WIDTH_GOTO_LINE;
    } else {
        $input_width = FOOTER_INPUT_WIDTH_DEFAULT;
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
            push @_out, substr($display_value, 0, $sel_s);
        }
        push @_out, $sel_bg . $sel_fg;
        push @_out, substr($display_value, $sel_s, $sel_e - $sel_s);
        push @_out, $input_bg . $input_fg;
        if ($sel_e < length($display_value)) {
            push @_out, substr($display_value, $sel_e);
        }
    } else {
        push @_out, $display_value;
    }

    # Fill remaining input area
    my $fill = $input_width - length($display_value);
    push @_out, ' ' x $fill if $fill > 0;

    # Display hint in dimmed text
    push @_out, $theme->color('status_bg');
    if ($hint) {
        push @_out, $theme->color('status_dim');
        push @_out, $hint_str;
    }

    # Pad rest of status bar
    my $remaining = $cols - $prompt_len - $input_width - $hint_len;
    push @_out, ' ' x $remaining if $remaining > 0;

    push @_out, CLEAR_LINE;
    push @_out, RESET;

    return join('', @_out);
}

# =============================================================================
# Find Bar Rendering (incremental search in status bar)
# =============================================================================

# Colorize regex find input: highlight () capture groups with distinct colors
# Group numbers are assigned left-to-right by opening paren (matching Perl semantics)
sub _colorize_find_input {
    my ($class, $theme, $text, $default_fg) = @_;

    my @_out;
    my $len = length($text);
    my $group_num = 0;       # Next group number to assign
    my @group_stack;         # Stack of active group numbers (for nesting)
    my $i = 0;

    while ($i < $len) {
        my $ch = substr($text, $i, 1);

        # Skip escaped characters
        if ($ch eq '\\' && $i + 1 < $len) {
            push @_out, substr($text, $i, 2);
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
            push @_out, substr($text, $start, $i - $start);
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
                push @_out, $color . $ch;
            } else {
                # Non-capturing group: push placeholder
                push @group_stack, { num => 0, color => undef };
                push @_out, $ch;
            }
            $i++;
            next;
        }

        if ($ch eq ')' && @group_stack) {
            my $entry = pop @group_stack;
            if ($entry->{color}) {
                push @_out, $entry->{color} . $ch;
            } else {
                push @_out, $ch;
            }
            # Restore parent group color or default
            if (@group_stack && $group_stack[-1]{color}) {
                push @_out, $group_stack[-1]{color};
            } else {
                push @_out, $default_fg;
            }
            $i++;
            next;
        }

        # Regular character: use current group's color
        if (@group_stack && $group_stack[-1]{color}) {
            # Already in a colored group, color is set
        }
        push @_out, $ch;
        $i++;
    }

    # Restore default color
    push @_out, $default_fg;
    return join('', @_out);
}

# Colorize replace input: highlight $N tokens with capture group colors
sub _colorize_replace_input {
    my ($class, $theme, $text, $default_fg, $capture_count) = @_;

    my @_out;
    my $len = length($text);
    my $i = 0;

    while ($i < $len) {
        my $ch = substr($text, $i, 1);

        if ($ch eq '$' && $i + 1 < $len) {
            my $next = substr($text, $i + 1, 1);

            if ($next eq '$') {
                # $$ escape
                push @_out, '$$';
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
                    push @_out, $theme->color('status_dim') . $token . $default_fg;
                } elsif ($num <= $capture_count) {
                    # $N within range: use group color
                    my $color_idx = (($num - 1) % 4) + 1;
                    push @_out, $theme->color("capture_group_$color_idx") . $token . $default_fg;
                } else {
                    # Beyond capture count: no special color
                    push @_out, $token;
                }
                $i = $j;
                next;
            }
        }

        push @_out, $ch;
        $i++;
    }

    return join('', @_out);
}

sub _render_find_bar {
    my ($class, $theme, $find, $cols) = @_;

    my @_out;
    push @_out, $theme->color('status_bg') . $theme->color('status_fg');

    my $value = $find->{value} // '';
    my $regex_on = $find->{regex} // 0;
    my $case_on = $find->{case} // 0;
    my $replace_value = $find->{replace_value} // '';
    my $replace_all = $find->{replace_all} // 1;
    my $replace_active = $find->{replace_active} // 0;
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
        # Show navigation hint with match position
        $match_text = "\x{2191}\x{2193} " . ($current + 1) . ' of ' . $match_count;
        $match_text .= '...' if $is_searching;
    }

    # Rounded pill characters (nerd font or space fallback)
    my $rl = Zepto::Chars->get('round_left');
    my $rr = Zepto::Chars->get('round_right');

    # Build capture hint string (e.g. "$0 $1 $2") for status bar
    # Only show when regex mode is on AND the pattern actually has capture groups
    my $capture_hint = '';
    if ($regex_on && $capture_count > 0) {
        $capture_hint = '$0';
        for my $i (1 .. $capture_count) {
            $capture_hint .= " \$$i";
        }
    }
    my $capture_hint_width = length($capture_hint) ? length($capture_hint) + 1 : 0;  # +1 for space

    # Fixed widths for buttons/toggles on right side
    # ".* ^R" (9+1) + "Aa ^C" (9+1) + "X Esc" (9+1) + "✓ Enter" (11) + spaces
    my $right_side_width = FIND_BAR_RIGHT_SIDE_BASE_WIDTH + length($match_text) + $capture_hint_width;

    # Calculate input field widths (never overflows $cols -- see
    # find_bar_input_width's doc comment for why this matters)
    my $input_width = $class->find_bar_input_width($cols, $replace_active, $right_side_width);

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

    my $replace_field_start = $x;
    if ($replace_active) {
        # Replace label
        $content .= 'Replace:';
        $x += 8;

        # Replace input field (clickable)
        $replace_field_start = $x;
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
    }
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
    # Floor at 0, not 1: on a narrow terminal, forcing a minimum of 1 here
    # can add an extra character beyond what find_bar_input_width already
    # budgeted for, re-introducing a 1-char overflow in the tightest case
    # (see find_bar_input_width's doc comment -- this line contributed to
    # the same bugs.md P0 screen-corruption bug).
    $padding_needed = 0 if $padding_needed < 0;
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

    push @_out, $content;
    push @_out, CLEAR_LINE;
    push @_out, RESET;

    return join('', @_out);
}

sub _render_prompt {
    my ($class, $theme, $prompt, $cols, $rows) = @_;

    my @_out;
    my $bg = $theme->color('prompt_bg');
    my $fg = $theme->color('prompt_fg');
    push @_out, $bg . $fg;

    my $text = $prompt->{text} // '';
    my @options = @{$prompt->{options} // []};

    my $rl = Zepto::Chars->get('round_left');
    my $rr = Zepto::Chars->get('round_right');
    my $nerd_font = Zepto::Chars->enabled();

    # Warning icon + prompt text
    my $warn_icon = Zepto::Chars->get('warning');
    push @_out, " $warn_icon $text ";
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
            push @_out, $bg . $theme->color('prompt_pill_edge') . $rl;
            $x++;
        }
        push @_out, $theme->color('prompt_pill_bg') . $theme->color('prompt_pill_fg');
        # Render label then dimmed key
        if ($icon) {
            push @_out, " $icon $label ";
        } else {
            push @_out, " $label ";
        }
        push @_out, $fg . $key . $theme->color('prompt_pill_fg') . ' ';
        if ($nerd_font) {
            push @_out, $bg . $theme->color('prompt_pill_edge') . $rr;
            $x++;
        }
        $x += length($pill_text);

        push @buttons, {
            key => lc($opt->{key}),
            x_start => $btn_start + 1,
            x_end => $x,
            y => $rows,
        };

        push @_out, $bg . $fg . ' ';
        $x++;
    }

    # Pad to fill status bar
    my $padding = $cols - $x;
    push @_out, $bg . ' ' x $padding if $padding > 0;

    push @_out, CLEAR_LINE;
    push @_out, RESET;

    $class->_set_prompt_buttons(\@buttons);

    return join('', @_out);
}

# =============================================================================
# File Picker Rendering
# =============================================================================

# =============================================================================
# Command Palette Rendering
# =============================================================================

sub _render_command_palette {
    my ($class, $theme, $palette, $total_rows, $total_cols) = @_;

    my @_out;

    my $query    = $palette->{query} // '';
    my $cursor   = $palette->{cursor} // 0;
    my $scroll   = $palette->{scroll} // 0;
    my $filtered = $palette->{filtered} // [];
    my $editor   = $palette->{editor};      # real Zepto::Editor — for generic
                                             # command-toggle-state queries
    my $ctrl     = $palette->{controller};  # PaletteController — for
                                             # palette-private fields
                                             # (_file_search_*, palette_visible_rows)

    # Palette dimensions — adapts to terminal width and mode
    my $mode = $palette->{mode} // 'commands';
    my $pal_width = $total_cols - 4;
    if ($mode eq 'find_in_files' || $mode eq 'files' || $mode eq 'recent_files') {
        $pal_width = PALETTE_WIDTH_WIDE if $pal_width > PALETTE_WIDTH_WIDE;  # File pickers: wide for long paths
    } elsif ($total_cols >= PALETTE_WIDTH_WIDE) {
        $pal_width = PALETTE_WIDTH_MEDIUM if $pal_width > PALETTE_WIDTH_MEDIUM;    # Wide terminal: moderately wider
    } else {
        $pal_width = PALETTE_WIDTH_NARROW if $pal_width > PALETTE_WIDTH_NARROW;    # Standard: default width
    }
    $pal_width = PALETTE_WIDTH_MIN if $pal_width < PALETTE_WIDTH_MIN;

    my $has_footer_row = ($mode eq 'find_in_files') ? 1 : 0;
    my $max_items = $total_rows - 6 - $has_footer_row;
    $max_items = PALETTE_MAX_ITEMS_MIN if $max_items < PALETTE_MAX_ITEMS_MIN;
    $max_items = PALETTE_MAX_ITEMS_MAX if $max_items > PALETTE_MAX_ITEMS_MAX;

    my $item_count = scalar @$filtered;
    # Fixed height: always use max_items so palette doesn't resize when filtering
    my $visible_items = $max_items;

    # Palette height: border(1) + filter(1) + separator(1) + items + [footer(1)] + border(1)
    my $pal_height = 3 + $visible_items + $has_footer_row + 1;

    # Center palette
    my $x = int(($total_cols - $pal_width) / 2);
    my $y = int(($total_rows - $pal_height) / 2);
    $x = 1 if $x < 1;
    $y = 2 if $y < 2;

    # Update visible rows for scroll management (write back to the palette
    # controller for scroll bookkeeping)
    if ($ctrl) {
        $ctrl->{palette_visible_rows} = $visible_items;
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

    # Tree branch chars for find-in-files result grouping
    my $tree_branch_ch = Zepto::Chars->get('tree_branch');  # ├
    my $tree_last_ch   = Zepto::Chars->get('tree_last');    # ╰
    my $tree_dash_ch   = Zepto::Chars->get('tree_dash');    # ─
    my $tree_fg        = $theme->color('tree_indent_fg');
    my $fsr_path_fg    = $theme->color('fsr_path_fg');
    my $fsr_path_active_fg = $theme->color('fsr_path_active_fg');

    # === Top border with title ===
    my $title;
    if ($mode eq 'recent_files') {
        $title = " " . CTRL_GLYPH . "E Recent Files ";
    } elsif ($mode eq 'files') {
        $title = " " . CTRL_GLYPH . "O Open File ";
    } elsif ($mode eq 'find_in_files') {
        my $scope = $ctrl->{_file_search_scope_label} // 'project';
        $title = " " . CTRL_GLYPH . "\x{21E7}F Find in Files ($scope) ";
    } else {
        $title = " " . CTRL_GLYPH . "\x{2423} Commands ";
    }
    my $title_len = length($title);
    my $border_left = int(($pal_width - 2 - $title_len) / 2);
    $border_left = 0 if $border_left < 0;
    my $border_right = $pal_width - 2 - $border_left - $title_len;
    $border_right = 0 if $border_right < 0;

    push @_out, _move_to($y, $x);
    push @_out, $bg . $border_fg;
    push @_out, $box_tl;
    push @_out, $box_h x $border_left;
    push @_out, $fg . $title;
    push @_out, $border_fg;
    push @_out, $box_h x $border_right;
    push @_out, $box_tr;

    # === Filter input row ===
    push @_out, _move_to($y + 1, $x);
    push @_out, $bg . $border_fg . $box_v;

    my $filter_icon = Zepto::Chars->get('filter');
    my $inner_width = $pal_width - 2;  # inside the box borders

    # Input area: icon + space + query + padding
    push @_out, $bg . $fg;
    push @_out, " $filter_icon ";
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
        push @_out, $input_fg;
        push @_out, substr($display_query, 0, $pal_sel_s) if $pal_sel_s > 0;
        push @_out, $sel_bg . $sel_fg;
        push @_out, substr($display_query, $pal_sel_s, $pal_sel_e - $pal_sel_s);
        push @_out, $bg . $input_fg;
        push @_out, substr($display_query, $pal_sel_e) if $pal_sel_e < length($display_query);
        push @_out, $fg;
    } else {
        push @_out, $input_fg;
        push @_out, $display_query;
        push @_out, $fg;
    }
    my $qpad = $input_area - length($display_query);
    push @_out, ' ' x $qpad if $qpad > 0;
    push @_out, ' ';

    push @_out, $border_fg . $box_v;

    # === Separator row ===
    push @_out, _move_to($y + 2, $x);
    push @_out, $bg . $border_fg;
    push @_out, "\x{251C}";  # ├
    push @_out, $box_h x ($pal_width - 2);
    push @_out, "\x{2524}";  # ┤

    # === Item rows ===
    my @buttons;
    my $current_section = '';

    # For find_in_files: determine the selected item's group to highlight its path header
    my $selected_group_idx = -1;
    if ($mode eq 'find_in_files' && $cursor < $item_count) {
        my $sel_item = $filtered->[$cursor];
        $selected_group_idx = $sel_item->{_group_idx} // -1;
    }

    for my $vi (0 .. $visible_items - 1) {
        my $item_idx = $scroll + $vi;
        my $row_y = $y + 3 + $vi;

        push @_out, _move_to($row_y, $x);
        push @_out, $bg . $border_fg . $box_v;

        if ($item_idx < $item_count) {
            my $cmd = $filtered->[$item_idx];

            # File search path header row (non-selectable, BOLD filename)
            if ($cmd->{_is_fsr_path}) {
                my $path_highlighted = ($selected_group_idx >= 0
                    && ($cmd->{_group_idx} // -2) == $selected_group_idx);
                # Filenames: BOLD + themed color on normal bg
                push @_out, $bg;
                if ($path_highlighted) {
                    push @_out, BOLD . $fsr_path_active_fg;
                } else {
                    push @_out, BOLD . $fsr_path_fg;
                }
                push @_out, "  ";
                my $ficon = Zepto::Chars->file_icon($cmd->{_filename});
                push @_out, "$ficon ";
                my $path_label = $cmd->{label} // '';
                my $max_path = $inner_width - 4;
                if (length($path_label) > $max_path) {
                    $path_label = _ellipsis($path_label, $max_path, 'start');
                }
                push @_out, $path_label;
                my $ppad = $inner_width - 4 - length($path_label);
                push @_out, RESET . $bg;  # Clear BOLD before padding
                push @_out, ' ' x $ppad if $ppad > 0;
                push @_out, $border_fg . $box_v;
                push @_out, RESET;
                next;
            }

            # Section header row (commands mode)
            if ($cmd->{_is_header}) {
                push @_out, $bg . $shortcut_fg;
                my $header_label = "  \x{2500}\x{2500} " . $cmd->{label} . " ";
                my $header_pad = $inner_width - length($header_label);
                $header_pad = 0 if $header_pad < 0;
                push @_out, $header_label;
                # Fill remaining space with light horizontal line
                push @_out, "\x{2500}" x $header_pad if $header_pad > 0;
                push @_out, $border_fg . $box_v;
                push @_out, RESET;
                next;
            }

            my $is_selected = ($item_idx == $cursor);

            # Row background
            if ($is_selected) {
                push @_out, $sel_bg . $sel_fg;
            } else {
                push @_out, $bg . $fg;
            }

            # File search content row — tree branch + match highlighting
            if ($cmd->{_is_fsr_content}) {
                my $row_bg = $is_selected ? $sel_bg : $bg;
                my $row_fg = $is_selected ? $sel_fg : $fg;

                # Tree branch prefix: "  ├─ " or "  ╰─ " (aligned under file icon)
                my $is_last = $cmd->{_is_last_in_group};
                my $branch = $is_last ? $tree_last_ch : $tree_branch_ch;
                my $tree_prefix = "  $branch$tree_dash_ch ";
                my $tree_prefix_len = 5;

                push @_out, $row_bg . $tree_fg . $tree_prefix;
                push @_out, $row_fg;

                my $label = $cmd->{label} // '';
                my $ms = $cmd->{_match_start} // -1;
                my $ml = $cmd->{_match_len} // 0;

                # Available width for label (tree prefix takes 5 chars)
                my $available_width = $inner_width - $tree_prefix_len;
                if (length($label) > $available_width) {
                    $label = _ellipsis($label, $available_width);
                }

                # Render with match highlighting
                my $match_hl_bg = $theme->color('match_bg');
                my $match_hl_fg = $theme->color('match_fg');

                if ($ms >= 0 && $ml > 0 && $ms < length($label)) {
                    my $before = substr($label, 0, $ms);
                    my $end_pos = $ms + $ml;
                    $end_pos = length($label) if $end_pos > length($label);
                    my $match  = substr($label, $ms, $end_pos - $ms);
                    my $after  = $end_pos < length($label) ? substr($label, $end_pos) : '';

                    push @_out, $before;
                    push @_out, $match_hl_bg . $match_hl_fg . $match;
                    push @_out, $row_bg . $row_fg . $after;
                } else {
                    push @_out, $label;
                }

                my $rpad = $available_width - length($label);
                push @_out, $row_bg;
                push @_out, ' ' x $rpad if $rpad > 0;

                push @buttons, {
                    y       => $row_y,
                    x_start => $x + 1,
                    x_end   => $x + $pal_width - 2,
                    index   => $item_idx,
                };
            }
            else {
                # Standard palette item rendering

                # Selection indicator
                my $prefix = $is_selected ? ($ar . ' ') : '  ';
                push @_out, $prefix;

                # Icon
                my $icon;
                if ($cmd->{_is_file}) {
                    $icon = Zepto::Chars->file_icon($cmd->{_filename});
                } elsif (($cmd->{pref} // '') eq 'theme') {
                    # Theme row: icon reflects the actual current mode
                    # (auto/dark/light), not a static moon regardless of state.
                    my $theme_state = Zepto::CommandRegistry->get_toggle_state($cmd, $editor) // 'dark';
                    $icon = Zepto::Chars->get("theme_$theme_state");
                } else {
                    $icon = Zepto::Chars->get($cmd->{icon} // 'menu');
                }
                push @_out, "$icon ";

                # Shortcut (truncate from start if too long, keeping the end)
                my $shortcut = $cmd->{shortcut} // '';
                my $shortcut_display = $shortcut;
                my $shortcut_width = length($shortcut_display);
                my $max_shortcut = int($inner_width / 2) - 4;
                $max_shortcut = PALETTE_SHORTCUT_WIDTH_MIN if $max_shortcut < PALETTE_SHORTCUT_WIDTH_MIN;
                if ($shortcut_width > $max_shortcut) {
                    $shortcut_display = _ellipsis($shortcut, $max_shortcut, 'start');
                    $shortcut_width = length($shortcut_display);
                }

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
                    $label = _ellipsis($label, $label_space);
                }

                push @_out, $label;
                my $label_pad = $label_space - length($label);
                push @_out, ' ' x $label_pad if $label_pad > 0;
                push @_out, ' ';

                # Shortcut (dimmed unless selected)
                if (!$is_selected) {
                    push @_out, $shortcut_fg;
                }
                push @_out, $shortcut_display;

                # Toggle state
                if ($toggle_width > 0) {
                    push @_out, ' ';
                    if ($is_selected) {
                        push @_out, $toggle_text;
                    } else {
                        push @_out, $shortcut_fg . $toggle_text;
                    }
                }

                # Pad to fill row
                my $content_len = 2 + 2 + length($label) + $label_pad + 1 + $shortcut_width + ($toggle_width > 0 ? 1 + $toggle_width : 0);
                my $row_pad = $inner_width - $content_len;
                if ($is_selected) {
                    push @_out, $sel_bg;
                } else {
                    push @_out, $bg;
                }
                push @_out, ' ' x $row_pad if $row_pad > 0;

                # Store button region for click handling
                push @buttons, {
                    y       => $row_y,
                    x_start => $x + 1,
                    x_end   => $x + $pal_width - 2,
                    index   => $item_idx,
                };
            }
        } else {
            # Empty row (fixed-height palette may have unfilled rows)
            push @_out, $bg . (' ' x $inner_width);
        }

        push @_out, $bg . $border_fg . $box_v;
        push @_out, RESET;
    }

    # === Footer row with pill buttons (find_in_files only) ===
    my $footer_y;
    if ($has_footer_row) {
        $footer_y = $y + 3 + $visible_items;
        push @_out, _move_to($footer_y, $x);
        push @_out, $bg . $border_fg . $box_v;

        # Render pills inside the footer row using find bar style
        my $rl = Zepto::Chars->get('round_left');
        my $rr = Zepto::Chars->get('round_right');
        my $regex_on = $ctrl ? ($ctrl->{_file_search_regex} // 0) : 0;
        my $case_on  = $ctrl ? ($ctrl->{_file_search_case} // 0) : 0;
        my $scope_label = $ctrl ? ($ctrl->{_file_search_scope_label} // 'project') : 'project';
        my $sym_ctrl = Zepto::CommandRegistry::SYM_CTRL();

        my $pill_content = '';
        my $pill_vis_len = 0;  # track visible width

        $pill_content .= $bg . ' ';
        $pill_vis_len += 1;

        # Regex pill — position tracking for click regions
        my $regex_pill_start = $x + 1 + $pill_vis_len;
        if ($regex_on) {
            $pill_content .= $bg . $theme->color('menu_active_edge') . $rl;
            $pill_content .= $theme->color('menu_active_bg') . $theme->color('menu_active_text');
            $pill_content .= ' .* ';
            $pill_content .= $theme->color('dropdown_shortcut') . $sym_ctrl . 'R';
            $pill_content .= $theme->color('menu_active_text') . ' ';
            $pill_content .= $bg . $theme->color('menu_active_edge') . $rr;
        } else {
            $pill_content .= $bg . $theme->color('menu_pill_edge') . $rl;
            $pill_content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
            $pill_content .= ' .* ';
            $pill_content .= $theme->color('dropdown_shortcut') . $sym_ctrl . 'R';
            $pill_content .= $theme->color('menu_pill_text') . ' ';
            $pill_content .= $bg . $theme->color('menu_pill_edge') . $rr;
        }
        $pill_vis_len += 9;  # pill width: edges(2) + " .* ^R "(7)

        $pill_content .= $bg . ' ';
        $pill_vis_len += 1;

        # Case pill
        my $case_pill_start = $x + 1 + $pill_vis_len;
        if ($case_on) {
            $pill_content .= $bg . $theme->color('menu_active_edge') . $rl;
            $pill_content .= $theme->color('menu_active_bg') . $theme->color('menu_active_text');
            $pill_content .= ' Aa ';
            $pill_content .= $theme->color('dropdown_shortcut') . $sym_ctrl . 'C';
            $pill_content .= $theme->color('menu_active_text') . ' ';
            $pill_content .= $bg . $theme->color('menu_active_edge') . $rr;
        } else {
            $pill_content .= $bg . $theme->color('menu_pill_edge') . $rl;
            $pill_content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
            $pill_content .= ' Aa ';
            $pill_content .= $theme->color('dropdown_shortcut') . $sym_ctrl . 'C';
            $pill_content .= $theme->color('menu_pill_text') . ' ';
            $pill_content .= $bg . $theme->color('menu_pill_edge') . $rr;
        }
        $pill_vis_len += 9;

        $pill_content .= $bg . ' ';
        $pill_vis_len += 1;

        # Scope pill (always inactive style)
        my $scope_pill_start = $x + 1 + $pill_vis_len;
        my $scope_text = " $scope_label ";
        my $scope_shortcut = 'Tab';
        my $scope_pill_width = 2 + length($scope_text) + length($scope_shortcut);
        $pill_content .= $bg . $theme->color('menu_pill_edge') . $rl;
        $pill_content .= $theme->color('menu_pill_bg') . $theme->color('menu_pill_text');
        $pill_content .= $scope_text;
        $pill_content .= $theme->color('dropdown_shortcut') . $scope_shortcut;
        $pill_content .= $theme->color('menu_pill_text') . ' ';
        $pill_content .= $bg . $theme->color('menu_pill_edge') . $rr;
        $pill_vis_len += $scope_pill_width + 1;  # +1 for trailing space in pill

        # Result count on the right (use actual match count, not item count)
        my $actual_count = ($ctrl && $ctrl->{_file_search_engine})
            ? $ctrl->{_file_search_engine}->{result_count} : 0;
        my $result_count_text;
        if ($ctrl && $ctrl->{_file_search_engine}
            && $ctrl->{_file_search_engine}->is_searching()) {
            $result_count_text = "searching\x{2026} ($actual_count)";
        } elsif ($ctrl && $ctrl->{_file_search_engine}
            && $actual_count >= $ctrl->{_file_search_engine}->{_max_results}) {
            $result_count_text = "$actual_count results (capped)";
        } else {
            my $result_word = $actual_count == 1 ? 'result' : 'results';
            $result_count_text = "$actual_count $result_word";
        }

        my $right_pad = $inner_width - $pill_vis_len - length($result_count_text) - 1;
        $right_pad = 1 if $right_pad < 1;
        $pill_content .= $bg . $fg;
        $pill_content .= ' ' x $right_pad;
        $pill_content .= $shortcut_fg . $result_count_text . ' ';

        push @_out, $pill_content;
        push @_out, $bg . $border_fg . $box_v;
        push @_out, RESET;

        # Store pill click regions
        push @buttons, {
            y => $footer_y,
            x_start => $regex_pill_start,
            x_end   => $regex_pill_start + 8,
            _action => 'toggle_regex',
        };
        push @buttons, {
            y => $footer_y,
            x_start => $case_pill_start,
            x_end   => $case_pill_start + 8,
            _action => 'toggle_case',
        };
        push @buttons, {
            y => $footer_y,
            x_start => $scope_pill_start,
            x_end   => $scope_pill_start + $scope_pill_width,
            _action => 'cycle_scope',
        };
    }

    # === Bottom border ===
    my $bottom_y = $y + 3 + $visible_items + $has_footer_row;
    push @_out, _move_to($bottom_y, $x);
    push @_out, $bg . $border_fg;
    push @_out, $box_bl;

    # Bottom border — clean (find_in_files shows counts in its footer row)
    my $count_text = '';

    my $bottom_border_avail = $pal_width - 2 - length($count_text);
    $bottom_border_avail = 0 if $bottom_border_avail < 0;
    my $bottom_border_left = int($bottom_border_avail / 2);
    my $bottom_border_right = $bottom_border_avail - $bottom_border_left;
    push @_out, $box_h x $bottom_border_left;
    if (length($count_text)) {
        push @_out, $fg . $count_text;
        push @_out, $border_fg;
    }
    push @_out, $box_h x $bottom_border_right;
    push @_out, $box_br;
    push @_out, RESET;

    $class->_set_palette_buttons(\@buttons);
    $class->_set_palette_geometry({
        x => $x, y => $y, width => $pal_width,
        filter_row => $y + 1, filter_x_start => $x + 4,
        filter_input_width => $pal_width - 6,
        footer_row => $footer_y,
    });

    return join('', @_out);
}

1;
