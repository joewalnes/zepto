package Zepto::CommandRegistry;
# =============================================================================
# CommandRegistry: Single source of truth for all editor commands
# =============================================================================
#
# Centralizes command definitions for the command palette, status bar pills,
# and keyboard shortcut dispatch. Each command has an id, label, icon,
# shortcut, section, type, priority, and method.
#
# core_nav => 1 (optional) marks a command as "core navigation" per
# docs/UI_GUIDELINES.md's Discoverability Contract: it must always have a
# persistent, always-visible on-screen hint in whatever context the user is
# currently in, even if that hint isn't a status-bar pill (priority => 0).
# This is the single source of truth for "must always be visible somewhere"
# — see tests/discoverability_core_nav.t, which checks
# `core_nav => 1 || priority > 0` for the command set named in the Contract.
#
# Sections group commands in the palette: FILE, EDIT, NAVIGATE, VIEW
# Types: action (one-shot), toggle (binary on/off), setting (multi-value)
#
# Status bar priority: commands with priority > 0 are candidates for the
# status bar's two modifier-grouped columns (see Renderer::_render_context_status_bar).
# A command joins the ⌃ (Ctrl) column if its shortcut starts with the Ctrl
# glyph, or the ⌥ (Alt) column if it starts with the Alt glyph; anything else
# (no shortcut, a bare function key, or a multi-modifier chord) is never a
# status bar pill — it's still reachable from the command palette.
# Lower priority number = higher importance = fits at narrower widths and is
# the last to degrade to a compact (icon+key, no label) form. Priority 1 in
# each column is guaranteed a minimum width reservation so it always renders
# (in full or compact form) whenever the terminal is wide enough for any
# pills at all.
# =============================================================================

use strict;
use warnings;
use utf8;

# Modifier key display symbols
use constant {
    SYM_CTRL  => "\x{2303}",  # ⌃
    SYM_ALT   => "\x{2325}",  # ⌥
    SYM_SHIFT => "\x{21E7}",  # ⇧
    SYM_SPACE => "\x{2423}",  # ␣
    SYM_UP    => "\x{2191}",  # ↑
    SYM_DOWN  => "\x{2193}",  # ↓
};

# Master command list — the single source of truth
my @COMMANDS = (
    # === FILE section ===
    {
        id       => 'new_file',
        label    => 'New File',
        icon     => 'new_file',
        shortcut => SYM_CTRL . 'N',
        section  => 'FILE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_new_file',
    },
    {
        id       => 'open_file',
        label    => 'Open File',
        icon     => 'folder_open',
        shortcut => SYM_CTRL . 'O/' . SYM_CTRL . 'P',
        section  => 'FILE',
        type     => 'action',
        priority => 2,   # status bar: ⌃ group (was a hardcoded fixed-right pill)
        method   => 'cmd_open_file',
    },
    {
        id       => 'save',
        label    => 'Save',
        icon     => 'save',
        shortcut => SYM_CTRL . 'S',
        section  => 'FILE',
        type     => 'action',
        priority => 1,   # status bar: ⌃ group, most useful action
        method   => 'cmd_save',
    },
    {
        id       => 'save_as',
        label    => 'Save As',
        icon     => 'save',
        shortcut => '',
        section  => 'FILE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_save_as',
    },
    {
        id       => 'close_tab',
        label    => 'Save and Close Tab',
        icon     => 'times',
        shortcut => SYM_CTRL . 'W',
        section  => 'FILE',
        type     => 'action',
        priority => 0,
        core_nav => 1,   # always-visible via the tab-bar corner hint, not a status-bar pill — see docs/UI_GUIDELINES.md
        method   => 'cmd_close_tab',
    },
    {
        id       => 'quit',
        label    => 'Quit',
        icon     => 'quit',
        shortcut => SYM_CTRL . 'Q',
        section  => 'FILE',
        type     => 'action',
        priority => 0,
        core_nav => 1,   # always-visible via the tab-bar corner hint, not a status-bar pill — see docs/UI_GUIDELINES.md
        method   => 'cmd_quit',
    },
    {
        id       => 'next_tab',
        label    => 'Next Tab',
        icon     => 'chevron_down',
        shortcut => SYM_ALT . '.',
        section  => 'FILE',
        type     => 'action',
        priority => 0,
        core_nav => 1,   # always-visible via the tab-bar corner hint, not a status-bar pill — see docs/UI_GUIDELINES.md
        method   => 'cmd_next_tab',
    },
    {
        id       => 'prev_tab',
        label    => 'Prev Tab',
        icon     => 'chevron_up',
        shortcut => SYM_ALT . ',',
        section  => 'FILE',
        type     => 'action',
        priority => 0,
        core_nav => 1,   # always-visible via the tab-bar corner hint, not a status-bar pill — see docs/UI_GUIDELINES.md
        method   => 'cmd_prev_tab',
    },
    {
        id       => 'recent_files',
        label    => 'Recent Files',
        icon     => 'clock',
        shortcut => SYM_CTRL . 'E',
        section  => 'FILE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_recent_files',
    },
    {
        id       => 'toggle_tree',
        label    => 'File Tree',
        icon     => 'folder',
        shortcut => SYM_CTRL . 'B',
        section  => 'FILE',
        type     => 'toggle',
        pref     => 'show_tree',
        priority => 3,   # status bar: ⌃ group
        core_nav => 1,   # already covered via priority > 0, tagged for a single source of truth — see docs/UI_GUIDELINES.md
        method   => 'cmd_toggle_tree',
    },

    # === EDIT section ===
    {
        id       => 'undo',
        label    => 'Undo',
        icon     => 'undo',
        shortcut => SYM_CTRL . 'Z',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_undo',
    },
    {
        id       => 'redo',
        label    => 'Redo',
        icon     => 'redo',
        shortcut => SYM_CTRL . 'Y',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_redo',
    },
    {
        id       => 'cut',
        label    => 'Cut',
        icon     => 'cut',
        shortcut => SYM_CTRL . 'X',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_cut',
    },
    {
        id       => 'copy',
        label    => 'Copy',
        icon     => 'copy',
        shortcut => SYM_CTRL . 'C',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_copy',
    },
    {
        id       => 'paste',
        label    => 'Paste',
        icon     => 'paste',
        shortcut => SYM_CTRL . 'V',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_paste',
    },
    {
        id       => 'select_all',
        label    => 'Select All',
        icon     => 'select_all',
        shortcut => SYM_CTRL . 'A',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_select_all',
    },
    {
        id       => 'move_line_up',
        label    => 'Move Line Up',
        icon     => 'move_up',
        shortcut => SYM_ALT . SYM_UP,
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'do_move_line_up',
    },
    {
        id       => 'move_line_down',
        label    => 'Move Line Down',
        icon     => 'move_down',
        shortcut => SYM_ALT . SYM_DOWN,
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'do_move_line_down',
    },
    {
        id       => 'dup_line_up',
        label    => 'Duplicate Up',
        icon     => 'dup_up',
        shortcut => SYM_CTRL . 'U',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'do_duplicate_line_up',
    },
    {
        id       => 'select_next_occurrence',
        label    => 'Select Next Occurrence',
        icon     => 'search',
        shortcut => SYM_CTRL . 'D',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_select_next_occurrence',
    },
    {
        id       => 'dup_line_down',
        label    => 'Duplicate Down',
        icon     => 'dup_down',
        shortcut => SYM_ALT . 'U',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'do_duplicate_line_down',
    },
    {
        id       => 'toggle_comment',
        label    => 'Toggle Comment',
        icon     => 'comment',
        shortcut => SYM_CTRL . '/',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_toggle_comment',
    },
    {
        id       => 'transform',
        label    => 'Transform via Shell',
        icon     => 'terminal',
        shortcut => SYM_ALT . 'T',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_transform',
    },
    {
        id       => 'set_tab_width',
        label    => 'Tab Width',
        icon     => 'indent',
        shortcut => '',
        section  => 'EDIT',
        type     => 'action',
        priority => 0,
        method   => 'cmd_set_tab_width',
    },
    {
        id       => 'toggle_soft_tabs',
        label    => 'Soft Tabs (Spaces)',
        icon     => 'indent',
        shortcut => '',
        section  => 'EDIT',
        type     => 'toggle',
        pref     => 'soft_tabs',
        priority => 0,
        method   => 'cmd_toggle_soft_tabs',
    },
    {
        id       => 'toggle_auto_indent',
        label    => 'Auto Indent',
        icon     => 'indent',
        shortcut => '',
        section  => 'EDIT',
        type     => 'toggle',
        pref     => 'auto_indent',
        priority => 0,
        method   => 'cmd_toggle_auto_indent',
    },

    # === NAVIGATE section ===
    {
        id       => 'find',
        label    => 'Find',
        icon     => 'search',
        shortcut => SYM_CTRL . 'F',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 2,   # status bar: ⌃ group
        method   => 'cmd_find',
    },
    {
        id       => 'find_replace',
        label    => 'Find and Replace',
        icon     => 'search',
        shortcut => '',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_find_replace',
    },
    {
        id       => 'goto_line',
        label    => 'Go to Line',
        icon     => 'goto',
        shortcut => SYM_CTRL . 'G',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,  # Merged into cursor position pill (not a separate status bar pill)
        method   => 'cmd_goto_line',
    },
    {
        id       => 'find_next',
        label    => 'Find Next',
        icon     => 'chevron_down',
        shortcut => SYM_CTRL . 'J',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_find_next',
    },
    {
        id       => 'find_prev',
        label    => 'Find Prev',
        icon     => 'chevron_up',
        shortcut => SYM_CTRL . 'K',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_find_prev',
    },
    {
        id       => 'next_change',
        label    => 'Next Change',
        icon     => 'next_change',
        shortcut => SYM_ALT . 'N',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_next_change',
    },
    {
        id       => 'prev_change',
        label    => 'Prev Change',
        icon     => 'prev_change',
        shortcut => SYM_ALT . 'P',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_prev_change',
    },
    {
        id       => 'go_back',
        label    => 'Go Back',
        icon     => 'clock',
        shortcut => SYM_ALT . '-',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_go_back',
    },
    {
        id       => 'go_forward',
        label    => 'Go Forward',
        icon     => 'clock',
        shortcut => SYM_ALT . '=',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_go_forward',
    },
    {
        id       => 'find_in_files',
        label    => 'Find in Files',
        icon     => 'search',
        shortcut => SYM_CTRL . SYM_SHIFT . 'F',
        section  => 'NAVIGATE',
        type     => 'action',
        priority => 0,
        method   => 'cmd_find_in_files',
    },

    # === VIEW section ===
    {
        id       => 'toggle_word_wrap',
        label    => 'Word Wrap',
        icon     => 'wrap',
        shortcut => SYM_ALT . 'Z',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'word_wrap',
        priority => 1,   # status bar: ⌥ group, most useful toggle
        method   => 'cmd_toggle_word_wrap',
    },
    {
        id       => 'toggle_column_mode',
        label    => 'Column Mode',
        icon     => 'columns',
        shortcut => SYM_ALT . 'C',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => undef,          # managed by view, not prefs
        priority => 2,   # status bar: ⌥ group
        method   => 'cmd_toggle_column_mode',
    },
    {
        id       => 'toggle_diff',
        label    => 'Diff View',
        icon     => 'diff',
        shortcut => SYM_ALT . 'D',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => undef,          # managed per-view
        priority => 2,   # status bar: ⌥ group
        method   => 'cmd_toggle_diff',
    },
    {
        id       => 'toggle_minimap',
        label    => 'Minimap',
        icon     => 'minimap',
        shortcut => SYM_ALT . 'M',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'show_minimap',
        priority => 3,   # status bar: ⌥ group
        method   => 'cmd_toggle_minimap',
    },
    {
        id       => 'toggle_nerd_font',
        label    => 'Nerd Font',
        icon     => 'keyboard',
        shortcut => SYM_ALT . 'I',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'nerd_font',
        priority => 5,   # status bar: ⌥ group, rarely toggled
        method   => 'cmd_toggle_nerd_font',
    },
    {
        id       => 'toggle_theme',
        label    => 'Theme',
        icon     => 'theme_dark',    # dynamic: theme_auto/theme_dark/theme_light
        shortcut => SYM_CTRL . 'T',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'theme',
        priority => 4,   # status bar: ⌃ group
        method   => 'cmd_toggle_theme',
    },
    # Explicit theme-mode picks. The 'toggle_theme' row above (⌃T) shows the
    # current mode ([auto]/[dark]/[light]) and toggles between explicit
    # dark/light; these three jump directly to a specific mode, including
    # back into 'auto' — which ⌃T deliberately never does on its own (see
    # cmd_toggle_theme in Editor/Commands.pm).
    {
        id       => 'theme_set_auto',
        label    => 'Theme: Auto',
        icon     => 'theme_auto',
        shortcut => '',
        section  => 'VIEW',
        type     => 'action',
        priority => 0,
        method   => 'cmd_set_theme_auto',
    },
    {
        id       => 'theme_set_dark',
        label    => 'Theme: Dark',
        icon     => 'theme_dark',
        shortcut => '',
        section  => 'VIEW',
        type     => 'action',
        priority => 0,
        method   => 'cmd_set_theme_dark',
    },
    {
        id       => 'theme_set_light',
        label    => 'Theme: Light',
        icon     => 'theme_light',
        shortcut => '',
        section  => 'VIEW',
        type     => 'action',
        priority => 0,
        method   => 'cmd_set_theme_light',
    },
    {
        id       => 'toggle_autocomplete',
        label    => 'Auto Complete',
        icon     => 'keyboard',
        shortcut => '',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'auto_complete',
        priority => 0,
        method   => 'cmd_toggle_autocomplete',
    },
    {
        id       => 'toggle_auto_pairs',
        label    => 'Auto Pairs',
        icon     => 'keyboard',
        shortcut => '',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'auto_pairs',
        priority => 0,
        method   => 'cmd_toggle_auto_pairs',
    },
    {
        id       => 'toggle_restore_session',
        label    => 'Restore Session on Startup',
        icon     => 'clock',
        shortcut => '',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'restore_session',
        priority => 0,
        method   => 'cmd_toggle_restore_session',
    },
    {
        id       => 'toggle_mouse',
        label    => 'Mouse',
        icon     => 'settings',
        shortcut => '',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'mouse_enabled',
        priority => 0,
        method   => 'cmd_toggle_mouse',
    },
    {
        id       => 'toggle_search_wrap',
        label    => 'Search Wrap Around',
        icon     => 'search',
        shortcut => '',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'search_wrap',
        priority => 0,
        method   => 'cmd_toggle_search_wrap',
    },
    {
        id       => 'toggle_markdown_tables',
        label    => 'Markdown Table Rendering',
        icon     => 'settings',
        shortcut => '',
        section  => 'VIEW',
        type     => 'toggle',
        pref     => 'render_markdown_tables',
        priority => 0,
        method   => 'cmd_toggle_markdown_tables',
    },

    # === TRANSFORM section ===
    # Built-in, pure-Perl text transforms — no shell exec, unlike
    # "Transform via Shell" (⌥T, EDIT section, unchanged). Operate on
    # the current selection, or the whole document if nothing is
    # selected — same scoping ⌥T already uses.
    {
        id       => 'transform_uppercase',
        label    => 'Uppercase',
        icon     => 'terminal',
        shortcut => '',
        section  => 'TRANSFORM',
        type     => 'action',
        priority => 0,
        method   => 'cmd_transform_uppercase',
    },
    {
        id       => 'transform_lowercase',
        label    => 'Lowercase',
        icon     => 'terminal',
        shortcut => '',
        section  => 'TRANSFORM',
        type     => 'action',
        priority => 0,
        method   => 'cmd_transform_lowercase',
    },
    {
        id       => 'transform_sort_lines',
        label    => 'Sort Lines',
        icon     => 'terminal',
        shortcut => '',
        section  => 'TRANSFORM',
        type     => 'action',
        priority => 0,
        method   => 'cmd_transform_sort_lines',
    },
    {
        id       => 'transform_reverse_lines',
        label    => 'Reverse Lines',
        icon     => 'terminal',
        shortcut => '',
        section  => 'TRANSFORM',
        type     => 'action',
        priority => 0,
        method   => 'cmd_transform_reverse_lines',
    },
    {
        id       => 'transform_unique_lines',
        label    => 'Unique Lines',
        icon     => 'terminal',
        shortcut => '',
        section  => 'TRANSFORM',
        type     => 'action',
        priority => 0,
        method   => 'cmd_transform_unique_lines',
    },

    # === AI section ===
    {
        id       => 'ai_setup',
        label    => 'AI Completion: Setup',
        icon     => 'keyboard',
        shortcut => '',
        section  => 'AI',
        type     => 'action',
        priority => 0,
        method   => 'cmd_ai_setup',
    },
    {
        id       => 'toggle_ai',
        label    => 'AI Completion',
        icon     => 'keyboard',
        shortcut => '',
        section  => 'AI',
        type     => 'toggle',
        priority => 0,
        method   => 'cmd_toggle_ai',
    },

    # === DOCUMENTATION section ===
    {
        id       => 'doc_about',
        label    => 'About Zepto',
        icon     => 'palette',
        shortcut => '',
        section  => 'DOCUMENTATION',
        type     => 'action',
        priority => 0,
        method   => 'cmd_doc_about',
    },
    {
        id       => 'doc_tutorial',
        label    => 'Tutorial',
        icon     => 'keyboard',
        shortcut => 'F1',
        section  => 'DOCUMENTATION',
        type     => 'action',
        # Not shown as a status bar pill: F1 has no ⌃/⌥ modifier so it
        # doesn't belong in either grouped column (see status bar rework,
        # bugs.md). Still discoverable via palette and the F1 key itself.
        priority => 0,
        method   => 'cmd_doc_tutorial',
    },
    {
        id       => 'doc_changelog',
        label    => 'Changelog',
        icon     => 'clock',
        shortcut => '',
        section  => 'DOCUMENTATION',
        type     => 'action',
        priority => 0,
        method   => 'cmd_doc_changelog',
    },
    {
        id       => 'doc_license',
        label    => 'License & Credits',
        icon     => 'keyboard',
        shortcut => '',
        section  => 'DOCUMENTATION',
        type     => 'action',
        priority => 0,
        method   => 'cmd_doc_license',
    },

    # === DIAGNOSTICS section ===
    {
        id       => 'show_perf_log',
        label    => 'Performance Log',
        icon     => 'clock',
        shortcut => '',
        section  => 'DIAGNOSTICS',
        type     => 'action',
        priority => 0,
        method   => 'cmd_show_perf_log',
    },
);

# Build lookup index by id
my %BY_ID = map { $_->{id} => $_ } @COMMANDS;

# Section ordering for palette display
my @SECTION_ORDER = ('FILE', 'EDIT', 'NAVIGATE', 'VIEW', 'TRANSFORM', 'AI', 'DOCUMENTATION', 'DIAGNOSTICS');

# =============================================================================
# Public API
# =============================================================================

# Return all commands as a list of hashrefs
sub all_commands {
    return @COMMANDS;
}

# Return commands grouped by section (ordered)
# Returns: ( { name => 'FILE', items => [...] }, { name => 'EDIT', ... }, ... )
sub commands_by_section {
    my @result;
    for my $section (@SECTION_ORDER) {
        my @items = grep { $_->{section} eq $section } @COMMANDS;
        push @result, { name => $section, items => \@items } if @items;
    }
    return @result;
}

# Return commands suitable for the status bar at a given width
# $context: 'document', 'file_tree', etc.
# $width: terminal columns available
# Returns list of commands sorted by priority, filtered to fit
sub commands_for_status_bar {
    my ($class, $context, $width, $editor) = @_;

    # Only show status bar pills in document context for now
    return () unless $context eq 'document';

    # Collect commands with priority > 0
    my @candidates = grep { $_->{priority} > 0 } @COMMANDS;

    # Sort by priority (lower number = higher priority)
    @candidates = sort { $a->{priority} <=> $b->{priority} } @candidates;

    return @candidates;
}

# Find a command by id
sub find_command {
    my ($class, $id) = @_;
    return $BY_ID{$id};
}

# Fuzzy filter commands by query string
# Returns list of matching commands sorted by relevance score (descending)
sub filter_commands {
    my ($class, $query) = @_;

    return @COMMANDS unless defined $query && length($query) > 0;

    $query = lc($query);
    my @results;

    for my $cmd (@COMMANDS) {
        my $score = _fuzzy_score($query, lc($cmd->{label}));
        if ($score > 0) {
            push @results, { command => $cmd, score => $score };
        }
    }

    # Also match against shortcut display string
    for my $cmd (@COMMANDS) {
        next if grep { $_->{command}{id} eq $cmd->{id} } @results;
        my $shortcut_lower = lc($cmd->{shortcut} // '');
        if (index($shortcut_lower, $query) >= 0) {
            push @results, { command => $cmd, score => 1 };
        }
    }

    @results = sort { $b->{score} <=> $a->{score} } @results;
    return map { $_->{command} } @results;
}

# Execute a command by id on an editor instance
sub execute {
    my ($class, $editor, $id) = @_;
    my $cmd = $BY_ID{$id};
    return unless $cmd;

    my $method = $cmd->{method};
    if ($editor->can($method)) {
        $editor->$method();
        return 1;
    }
    return 0;
}

# Get toggle state for a command (returns undef if not a toggle)
sub get_toggle_state {
    my ($class, $cmd, $editor) = @_;
    return undef unless $cmd->{type} eq 'toggle';

    my $pref = $cmd->{pref};

    # Special cases: state managed by view, not preferences
    if ($cmd->{id} eq 'toggle_column_mode') {
        my $view = $editor->active_view();
        return $view ? $view->column_select() : 0;
    }
    if ($cmd->{id} eq 'toggle_diff') {
        return $editor->{diff_expanded} ? 1 : 0;
    }
    # Word wrap: effective state considers per-view override > filetype > global pref
    if ($cmd->{id} eq 'toggle_word_wrap') {
        return $editor->_effective_word_wrap() ? 1 : 0;
    }
    # File tree: per-window state, not from prefs
    if ($cmd->{id} eq 'toggle_tree') {
        return $editor->{_show_tree} ? 1 : 0;
    }
    # AI completion: check AIComplete module
    if ($cmd->{id} eq 'toggle_ai') {
        return ($editor->{_ai_complete} && $editor->{_ai_complete}->is_enabled()) ? 1 : 0;
    }

    # Standard preference-based toggle
    if ($pref) {
        my $prefs = $editor->{prefs};
        my $val = $prefs->get($pref);
        # For theme, return the value itself (dark/light), not 0/1
        if ($pref eq 'theme') {
            return $val;
        }
        return $val ? 1 : 0;
    }

    return undef;
}

# Get display state string for a toggle command
sub get_toggle_display {
    my ($class, $cmd, $editor) = @_;
    my $state = $class->get_toggle_state($cmd, $editor);
    return '' unless defined $state;

    if ($cmd->{pref} && $cmd->{pref} eq 'theme') {
        return $state;  # 'dark' or 'light'
    }
    return $state ? 'on' : 'off';
}

# Return section order
sub section_order {
    return @SECTION_ORDER;
}

# =============================================================================
# Internal: Fuzzy matching
# =============================================================================

# Score a query against a target string using subsequence matching
# Returns 0 if no match, higher scores for better matches
sub _fuzzy_score {
    my ($query, $target) = @_;

    my @qchars = split //, $query;
    my @tchars = split //, $target;

    my $qi = 0;  # query index
    my $score = 0;
    my $consecutive = 0;
    my $first_match = -1;

    for my $ti (0 .. $#tchars) {
        last if $qi >= @qchars;
        if ($tchars[$ti] eq $qchars[$qi]) {
            $qi++;
            $consecutive++;
            # Bonus for consecutive matches
            $score += $consecutive;
            # Bonus for matching at word start
            if ($ti == 0 || $tchars[$ti - 1] eq ' ' || $tchars[$ti - 1] eq '_') {
                $score += 5;
            }
            $first_match = $ti if $first_match < 0;
        } else {
            $consecutive = 0;
        }
    }

    # All query chars must match
    return 0 unless $qi >= @qchars;

    # Bonus for matching near the start
    $score += 3 if $first_match == 0;

    # Bonus for exact prefix match
    if (substr($target, 0, length($query)) eq $query) {
        $score += 10;
    }

    return $score;
}

1;
