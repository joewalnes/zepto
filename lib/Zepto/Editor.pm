package Zepto::Editor;
# =============================================================================
# Editor: Main orchestrator for the Zepto editor
# =============================================================================
#
# Coordinates all components:
#   - Document: text content and undo/redo
#   - View: cursor, selection, viewport
#   - Terminal: raw mode, I/O
#   - Renderer: screen drawing
#   - InputParser: keyboard/mouse events
#   - Preferences: configuration
#
# Handles the main event loop and all editor commands.
# =============================================================================

use strict;
use warnings;
use utf8;
use Carp;
use File::Spec;
use Time::HiRes qw(time);

use Exporter 'import';
our @EXPORT_OK = qw(STATE_EDITING STATE_PALETTE STATE_DIALOG STATE_PROMPT STATE_FOOTER_INPUT STATE_FIND STATE_QUIT);

# Version for crash reports
our $VERSION = '0.1.0';

use Zepto::Document;
use Zepto::View;
use Zepto::Terminal;
use Zepto::Renderer;
use Zepto::InputParser;
use Zepto::Preferences;
use Zepto::Theme;
use Zepto::Highlighter;
use Zepto::FindEngine;
use Zepto::LineMap;
use Zepto::WrapMap;
use Zepto::Editor::TabManager;
use Zepto::FileTree;
use Zepto::InputWidget;

# Editor states
use constant {
    STATE_EDITING      => 'editing',
    STATE_PALETTE      => 'palette',
    STATE_DIALOG       => 'dialog',
    STATE_PROMPT       => 'prompt',        # Simple choice in status bar
    STATE_FOOTER_INPUT => 'footer_input',  # Text input in status bar
    STATE_FIND         => 'find',          # Incremental find in status bar
    STATE_QUIT         => 'quit',
};

# Load command and menu modules (they add methods to this package)
use Zepto::Editor::Commands;
use Zepto::Editor::Palette;

# Timing and UI settings
use constant {
    INPUT_TIMEOUT_SEC           => 0.5,   # Seconds to wait for input
    RESERVED_ROWS               => 3,     # Rows for tab bar + ruler bar + status bar
    EXTERNAL_CHECK_INTERVAL_SEC => 1.0,   # How often to stat() for external file changes
};

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
        # Core components
        tab_manager => Zepto::Editor::TabManager->new(),
        terminal    => $opts{terminal} // Zepto::Terminal->new(),
        parser      => Zepto::InputParser->new(),
        prefs       => $opts{prefs} // Zepto::Preferences->new(),
        theme       => undef,

        # UI state
        state        => STATE_EDITING,
        dialog       => undef,
        message      => '',
        message_time => 0,

        # Search state
        search_term   => '',
        search_replace => '',
        last_search_pos => 0,

        # Incremental find state
        find_widget       => undef,   # InputWidget for search field
        find_current      => 0,       # Index of current match (0-based)
        find_regex        => 1,       # Regex mode enabled (on by default)
        find_case         => 0,       # Case-sensitive enabled

        # Replace state (extension of find)
        find_replace_widget => undef,   # InputWidget for replace field
        find_replace_active => 0,       # Is replace field visible?
        find_focus          => 'find',  # Which field has focus: 'find' or 'replace'
        find_replace_all    => 1,       # Replace all mode (vs replace one)

        # Clipboard
        clipboard          => '',
        clipboard_columnar => 0,

        # Quit confirmation
        quit_pending => 0,

        # Mouse button state for reliable drag detection
        mouse_button_down => 0,

        # Initial file paths from command line (supports both 'file' and 'files')
        initial_file  => $opts{file},  # backward compat for tests
        initial_files => $opts{files} // ($opts{file} ? [$opts{file}] : []),

        # Prompt state (for status bar prompts)
        prompt       => undef,

        # Footer input state (for text input in status bar)
        footer_input => undef,

        # File tree state
        file_tree            => undef,
        tree_border_dragging => 0,
        focus_tree           => $opts{focus_tree} // 0,

        # Title cache — avoids redundant terminal writes
        _last_title => '',

        # Command palette state
        palette_widget       => undef,  # InputWidget for filter query
        palette_cursor       => 0,
        palette_scroll       => 0,
        palette_filtered     => [],
        palette_visible_rows => 15,  # updated during render
        palette_mode         => 'commands',  # 'commands' or 'recent_files'

        # Recent files tracking
        _recent_files        => [],  # Ordered list of recent file paths (most recent first)

        # Location history (back/forward navigation)
        _loc_back_stack      => [],  # Stack of { file => path, line => N, col => N }
        _loc_forward_stack   => [],  # Forward stack for redo

        # Performance profiling
        _perf      => {},   # Subsystem flags set during each frame
        _perf_log  => [],   # Top 20 slowest frames (sorted descending by total_ms)
    }, $class;

    # Initialize theme
    $self->{theme} = Zepto::Theme->get_theme($self->{prefs}->theme());

    return $self;
}

# --- Tab accessor convenience methods ---
sub active_doc        { $_[0]->{tab_manager}->active_doc() }
sub active_view       { $_[0]->{tab_manager}->active_view() }
sub active_find_engine { $_[0]->{tab_manager}->active_find_engine() }
sub active_highlighter { $_[0]->{tab_manager}->active_highlighter() }
sub active_file_path  { $_[0]->{tab_manager}->active_file_path() }
sub active_tab        { $_[0]->{tab_manager}->active_tab() }

# Resolve effective word wrap state for active view:
# explicit per-view toggle > filetype default > global preference
sub _effective_word_wrap {
    my ($self) = @_;
    my $view = $self->active_view();
    return 0 unless $view;

    # Per-view explicit override wins
    my $override = $view->word_wrap_override();
    return $override if defined $override;

    # Filetype default
    my $doc = $self->active_doc();
    if ($doc) {
        return 1 if $self->{prefs}->should_default_wrap($doc->filename());
    }

    # Global preference
    return $self->{prefs}->word_wrap();
}

# =============================================================================
# Recent Files
# =============================================================================

use constant RECENT_FILES_MAX => 50;

sub _recent_files_path {
    my $home = $ENV{HOME} || (getpwuid($<))[7] || '.';
    return "$home/.config/zepto/recent_files";
}

sub _load_recent_files {
    my ($self) = @_;
    my $path = $self->_recent_files_path();
    return unless -f $path;

    my @files;
    if (open my $fh, '<', $path) {
        while (my $line = <$fh>) {
            chomp $line;
            push @files, $line if length($line) && -f $line;
        }
        close $fh;
    }
    $self->{_recent_files} = \@files;
}

sub _save_recent_files {
    my ($self) = @_;
    my $path = $self->_recent_files_path();

    # Ensure directory exists
    my $dir = $path;
    $dir =~ s{/[^/]+$}{};
    if (!-d $dir) {
        # Create directory recursively
        my @parts = split m{/}, $dir;
        my $built = '';
        for my $part (@parts) {
            $built .= "/$part";
            next if -d $built;
            mkdir $built or return;  # Silently fail
        }
    }

    if (open my $fh, '>', $path) {
        for my $file (@{$self->{_recent_files}}) {
            print $fh "$file\n";
        }
        close $fh;
    }
}

sub _track_recent_file {
    my ($self, $file_path) = @_;
    return unless defined $file_path && length($file_path);

    # Resolve to absolute path
    my $abs_path = File::Spec->rel2abs($file_path);

    # Remove if already in list (we'll re-add at front)
    my @files = grep { $_ ne $abs_path } @{$self->{_recent_files}};

    # Add to front
    unshift @files, $abs_path;

    # Trim to max
    splice @files, RECENT_FILES_MAX if @files > RECENT_FILES_MAX;

    $self->{_recent_files} = \@files;
    $self->_save_recent_files();
}

# =============================================================================
# Location History (back/forward navigation)
# =============================================================================

use constant LOC_HISTORY_MAX => 100;

# Record current location before a major jump
sub _record_location {
    my ($self) = @_;
    my $view = $self->active_view();
    return unless $view;

    my $loc = {
        file => $self->active_file_path() // '',
        line => $view->cursor_line(),
        col  => $view->cursor_col(),
    };

    # Don't record if same as top of back stack (same file and line)
    my $stack = $self->{_loc_back_stack};
    if (@$stack) {
        my $top = $stack->[-1];
        return if $top->{file} eq $loc->{file} && $top->{line} == $loc->{line};
    }

    push @$stack, $loc;
    # Trim to max
    shift @$stack if @$stack > LOC_HISTORY_MAX;

    # Clear forward stack — new navigation branch
    $self->{_loc_forward_stack} = [];
}

sub cmd_go_back {
    my ($self) = @_;
    my $stack = $self->{_loc_back_stack};
    return unless @$stack;

    # Push current location to forward stack
    my $view = $self->active_view();
    if ($view) {
        push @{$self->{_loc_forward_stack}}, {
            file => $self->active_file_path() // '',
            line => $view->cursor_line(),
            col  => $view->cursor_col(),
        };
    }

    my $loc = pop @$stack;
    $self->_jump_to_location($loc);
}

sub cmd_go_forward {
    my ($self) = @_;
    my $fwd = $self->{_loc_forward_stack};
    return unless @$fwd;

    # Push current location to back stack
    my $view = $self->active_view();
    if ($view) {
        push @{$self->{_loc_back_stack}}, {
            file => $self->active_file_path() // '',
            line => $view->cursor_line(),
            col  => $view->cursor_col(),
        };
    }

    my $loc = pop @$fwd;
    $self->_jump_to_location($loc);
}

sub _jump_to_location {
    my ($self, $loc) = @_;

    # Switch file if needed
    my $current_file = $self->active_file_path() // '';
    if ($loc->{file} ne $current_file && $loc->{file} ne '') {
        # Try to find open tab with this file
        my $tabs = $self->{tab_manager}->{tabs};
        my $found = 0;
        for my $i (0 .. $#$tabs) {
            if (($tabs->[$i]{file_path} // '') eq $loc->{file}) {
                $self->{tab_manager}->switch_to($i);
                $found = 1;
                last;
            }
        }
        # If not found among open tabs, try to open the file
        unless ($found) {
            if (-f $loc->{file}) {
                $self->_load_file($loc->{file});
            } else {
                return;  # File no longer exists, skip
            }
        }
    }

    # Set cursor position
    my $view = $self->active_view();
    return unless $view;
    my $doc = $self->active_doc();
    my $max_line = $doc->line_count() - 1;
    my $line = $loc->{line};
    $line = $max_line if $line > $max_line;
    $view->set_cursor($line, $loc->{col}, 0);
}

sub _create_document_state {
    my ($self, $file_path, %opts) = @_;

    my $doc;
    if ($file_path && -f $file_path) {
        $doc = Zepto::Document->load($file_path, skip_vcs => $opts{skip_vcs});
    } else {
        $doc = Zepto::Document->new(
            path => $file_path,
            ($opts{skip_vcs} ? (skip_vcs => 1) : ()),
        );
    }

    my $highlighter = Zepto::Highlighter->new();
    $highlighter->set_file($file_path);

    # Shebang detection
    if (!$highlighter->has_grammar && $doc->line_count() > 0) {
        my $first_line = $doc->get_line_content(0);
        $highlighter->detect_from_shebang($first_line);
    }

    my ($rows, $cols) = $self->{terminal}->get_size();
    my $line_count = $doc->line_count();
    my $gutter_width = Zepto::Renderer->get_gutter_width($line_count);
    my $text_width = $cols - $gutter_width;
    $text_width = Zepto::Renderer::MIN_TEXT_WIDTH if $text_width < Zepto::Renderer::MIN_TEXT_WIDTH;

    my $view = Zepto::View->new(
        document => $doc,
        viewport_rows => $rows - RESERVED_ROWS,
        viewport_cols => $text_width,
    );

    my $find_engine = Zepto::FindEngine->new(
        document => $doc,
    );

    return ($doc, $view, $find_engine, $highlighter);
}


# =============================================================================
# Initialization
# =============================================================================

sub init {
    my ($self) = @_;

    my $term = $self->{terminal};

    # Set process name (shows in ps/top)
    $0 = 'zepto';

    # Set cursor color and shape BEFORE raw mode
    my $cursor_color = $self->{theme}->color('cursor_color');
    if ($cursor_color) {
        print STDOUT "\x1b]12;${cursor_color}\x1b\\";
    }
    print STDOUT "\x1b[5 q";
    STDOUT->flush();

    # Setup terminal
    $term->enable_raw_mode();
    $term->enter_alt_screen();
    $term->enable_mouse() if $self->{prefs}->mouse_enabled();
    $term->get_size();

    # Setup SIGWINCH handler for terminal resize
    $SIG{WINCH} = sub {
        $term->refresh_size();
        $self->render();
    };

    # Special case: if the only arg is a directory, chdir to it
    my @files = @{$self->{initial_files}};
    if (@files == 1 && -d $files[0]) {
        chdir $files[0] or die "Cannot chdir to $files[0]: $!\n";
        @files = ();
        $self->{focus_tree} = 1;
    }

    # Load recent files list from disk
    $self->_load_recent_files();

    # Create tabs from initial files (or one empty tab if none specified)
    if (@files) {
        for my $file_path (@files) {
            my ($doc, $view, $find_engine, $highlighter) = $self->_create_document_state($file_path);
            $self->{tab_manager}->add_tab(
                document    => $doc,
                view        => $view,
                find_engine => $find_engine,
                highlighter => $highlighter,
                file_path   => $file_path,
            );
            # Track in recent files
            $self->_track_recent_file($file_path);
        }
        # Activate the first tab
        $self->{tab_manager}->set_active(0);
    } else {
        # No files specified — open one empty tab
        my ($doc, $view, $find_engine, $highlighter) = $self->_create_document_state(undef);
        $self->{tab_manager}->add_tab(
            document    => $doc,
            view        => $view,
            find_engine => $find_engine,
            highlighter => $highlighter,
        );
    }

    # Initialize file tree
    if ($self->{prefs}->show_tree()) {
        $self->{file_tree} = Zepto::FileTree->new(root_path => '.');
        if ($self->active_file_path()) {
            $self->{file_tree}->set_current_file($self->active_file_path());
            $self->{file_tree}->expand_to_path($self->active_file_path());
        }
        if ($self->{focus_tree}) {
            $self->{file_tree}->set_focused(1);
        }
    }

    return $self;
}


# =============================================================================
# Main Loop
# =============================================================================

sub run {
    my ($self) = @_;

    # Wrap everything in eval to catch crashes and ensure terminal cleanup
    my $error;
    eval {
        $self->init();
        $self->render();

        my $last_search_render = 0;  # Track last render during search

        while ($self->{state} ne STATE_QUIT) {
            # Use shorter timeout when background search is active
            my $searching = $self->active_find_engine() && $self->active_find_engine()->is_searching;
            my $timeout = $searching ? 0.01 : INPUT_TIMEOUT_SEC;  # 10ms vs 500ms

            # Read input with timeout
            my $input = $self->{terminal}->read_blocking($timeout);

            my $needs_render = 0;

            # Reset per-frame perf flags
            my $frame_start = time();
            $self->{_perf} = {};

            # Messages persist until replaced by a newer message (per UI guidelines).
            # Clear on any user input so normal status bar returns after next action.
            if ($self->{message} && length $input) {
                $self->{message} = '';
            }

            if (length $input) {
                $self->handle_input($input);
                $needs_render = 1;
                $last_search_render = 0;  # Reset throttle on user input
            }
            else {
                # Timeout with no input — flush pending escape sequences
                # (ESC alone becomes Escape key; ESC+char within timeout is Alt+char)
                if ($self->flush_pending_input()) {
                    $needs_render = 1;
                }
            }

            my $event_end = time();

            # Continue background search if active
            if ($searching) {
                my $term = $self->{terminal};
                my $engine = $self->active_find_engine();

                # Run ticks aggressively until input available or time limit
                my $batch_start = time();
                while ($engine->is_searching) {
                    $engine->tick(10);

                    # Check for input every few ticks to stay responsive
                    last if $term->has_input();

                    # Don't batch for more than 30ms to keep UI updating
                    last if (time() - $batch_start) > 0.03;
                }

                # Throttle render during search - only every 100ms
                my $now = time();
                if ($now - $last_search_render > 0.1) {
                    $needs_render = 1;
                    $last_search_render = $now;
                }

                # Always render when search completes
                if (!$engine->is_searching) {
                    $needs_render = 1;
                }
            }

            # Only render when needed to preserve cursor blink animation
            if ($needs_render) {
                $self->render();
                my $render_end = time();
                my $event_ms = ($event_end - $frame_start) * 1000;
                my $render_ms = ($render_end - $event_end) * 1000;
                my $total_ms = $event_ms + $render_ms;
                $self->_record_frame($frame_start, $total_ms, $event_ms, $render_ms, $input);
            }
        }
        1;
    } or do {
        $error = $@ || 'Unknown error';
    };

    # Always cleanup terminal, even on crash
    eval { $self->cleanup(); };

    # If we crashed, print crash report to stderr
    if ($error) {
        # Ensure terminal is fully reset for readable output
        print STDERR "\r\n";  # Start on fresh line
        system('stty', 'sane') if -t STDERR;  # Reset terminal settings
        $self->_print_crash_report($error);
        exit(1);
    }
}

sub _print_crash_report {
    my ($self, $error) = @_;

    # Get stack trace if not already present
    my $trace = $error;
    unless ($trace =~ /\n\s+at\s+\S+\s+line\s+\d+/) {
        $trace = Carp::longmess($error);
    }

    # Gather context
    my $file = $self->active_file_path() // '[no file]';
    my $state = $self->{state} // 'unknown';
    my $cursor_info = '';
    if ($self->active_view()) {
        my $line = $self->active_view()->cursor_line() + 1;
        my $col = $self->active_view()->cursor_col() + 1;
        $cursor_info = "Cursor: line $line, col $col";
    }
    my $doc_info = '';
    if ($self->active_doc()) {
        my $lines = $self->active_doc()->line_count();
        my $dirty = $self->active_doc()->is_dirty() ? ' (modified)' : '';
        $doc_info = "Document: $lines lines$dirty";
    }

    print STDERR <<EOF;

===============================================================================
ZEPTO CRASH REPORT
===============================================================================
Version: $VERSION
File: $file
State: $state
$cursor_info
$doc_info

Error:
$trace
===============================================================================

EOF
}

sub cleanup {
    my ($self) = @_;

    $self->{terminal}->cleanup();

    # Clear SIGWINCH handler
    $SIG{WINCH} = 'DEFAULT';
}

sub update_title {
    my ($self) = @_;

    my $title = 'zepto';
    if ($self->active_doc() && $self->active_doc()->path()) {
        $title .= ' - ' . $self->active_doc()->filename();
    }
    elsif ($self->active_file_path()) {
        my ($name) = $self->active_file_path() =~ m{([^/]+)$};
        $title .= ' - ' . $name if $name;
    }

    # Skip redundant terminal writes
    return if $self->{_last_title} eq $title;
    $self->{_last_title} = $title;
    $self->{terminal}->set_title($title);
}

# =============================================================================
# Input Handling
# =============================================================================

sub handle_input {
    my ($self, $input) = @_;

    my @events = $self->{parser}->parse($input);

    for my $event (@events) {
        $self->handle_event($event);
    }
}

# Flush any pending escape sequence (call after read timeout, not immediately)
sub flush_pending_input {
    my ($self) = @_;
    my $pending = $self->{parser}->flush_pending();
    if ($pending) {
        $self->handle_event($pending);
        return 1;
    }
    return 0;
}

sub handle_event {
    my ($self, $event) = @_;

    return unless $event;

    # Clear explicit scroll flag before processing any event.
    # Mouse scroll handlers will re-set it via scroll_up/scroll_down,
    # so the flag persists across scroll events but clears on any other action.
    if (my $view = $self->active_view()) {
        $view->clear_explicit_scroll();
    }

    # Global shortcuts that work in every UI state
    if ($event->{type} eq 'char' && Zepto::InputParser::has_modifier($event, 'ctrl')) {
        my $ch = lc($event->{char});
        if ($ch eq 'q' || $ch eq 's' || $ch eq 't') {
            $self->handle_ctrl_char($ch);
            return;
        }
    }

    # Route to appropriate handler based on state
    if ($self->{state} eq STATE_DIALOG) {
        $self->handle_dialog_event($event);
    }
    elsif ($self->{state} eq STATE_PALETTE) {
        $self->handle_palette_event($event);
    }
    elsif ($self->{state} eq STATE_PROMPT) {
        $self->handle_prompt_event($event);
    }
    elsif ($self->{state} eq STATE_FOOTER_INPUT) {
        $self->handle_footer_input_event($event);
    }
    elsif ($self->{state} eq STATE_FIND) {
        $self->handle_find_event($event);
    }
    else {
        $self->handle_editing_event($event);
    }
}

# =============================================================================
# Editing Event Handling
# =============================================================================

sub handle_editing_event {
    my ($self, $event) = @_;

    # If file tree is focused, check for global shortcuts first, then route to tree
    if ($self->{file_tree} && $self->{file_tree}->focused()) {
        # Ctrl+letter arrives as 'char' type with ctrl modifier, not 'key' type
        if ($event->{type} eq 'char' && Zepto::InputParser::has_modifier($event, 'ctrl')) {
            my $ch = lc($event->{char});
            # Global shortcuts that work regardless of focus
            if ($ch eq 'q' || $ch eq 's' || $ch eq 'n' ||
                $ch eq 'o' || $ch eq 'w' || $ch eq 'f' ||
                $ch eq 'e' || $ch eq 't' || $ch eq 'p' ||
                $ch eq 'b' || $ch eq ' ') {
                $self->handle_ctrl_char($ch);
                return;
            }
        }
        $self->handle_tree_event($event);
        return;
    }

    my $type = $event->{type};
    my $view = $self->active_view();
    my $doc = $self->active_doc();

    if ($type eq 'key') {
        my $key = $event->{key};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');
        my $shift = Zepto::InputParser::has_modifier($event, 'shift');
        my $alt = Zepto::InputParser::has_modifier($event, 'alt');

        # Navigation / Line movement
        # When column mode is active (toggled via ⌥C), arrows extend the
        # column selection rectangle instead of normal cursor movement.
        my $col_mode = $view->column_select();

        if ($key eq 'up') {
            if ($col_mode) { $self->do_column_select_up(); }
            elsif ($alt) { $self->do_move_line_up(); }
            else { $view->move_up($shift); }
        }
        elsif ($key eq 'down') {
            if ($col_mode) { $self->do_column_select_down(); }
            elsif ($alt) { $self->do_move_line_down(); }
            else { $view->move_down($shift); }
        }
        elsif ($key eq 'left')  {
            if ($col_mode) { $self->do_column_select_left(); }
            elsif ($alt) { $view->move_word_left($shift); }
            else { $view->move_left($shift); }
        }
        elsif ($key eq 'right') {
            if ($col_mode) { $self->do_column_select_right(); }
            elsif ($alt) { $view->move_word_right($shift); }
            else { $view->move_right($shift); }
        }
        elsif ($key eq 'home')  {
            if ($ctrl) { $view->move_to_document_start($shift); }
            else { $view->move_to_line_start($shift); }
        }
        elsif ($key eq 'end')   {
            if ($ctrl) { $view->move_to_document_end($shift); }
            else { $view->move_to_line_end($shift); }
        }
        elsif ($key eq 'pageup') {
            if ($ctrl && $shift) { $self->cmd_move_tab_left(); }
            elsif ($ctrl) { $self->cmd_prev_tab(); }
            else { $view->move_page_up($shift); }
        }
        elsif ($key eq 'pagedown') {
            if ($ctrl && $shift) { $self->cmd_move_tab_right(); }
            elsif ($ctrl) { $self->cmd_next_tab(); }
            else { $view->move_page_down($shift); }
        }

        # Editing keys
        elsif ($key eq 'backspace') { $self->do_backspace(); }
        elsif ($key eq 'delete')    { $self->do_delete(); }
        elsif ($key eq 'enter')     { $self->do_enter(); }
        elsif ($key eq 'tab')       {
            if ($shift) { $self->do_unindent(); }
            else { $self->do_indent(); }
        }

        # Escape - cancel/dismiss active mode
        elsif ($key eq 'escape') {
            if ($view->column_select()) {
                $view->exit_column_mode();
            }
            elsif ($view->has_selection()) {
                $view->clear_selection();
            }
            elsif ($view->line_map() && $view->line_map()->has_expanded_hunks()) {
                $view->line_map()->collapse_all();
            }
            $self->{quit_pending} = 0;
        }

        # Function keys (if any special handling needed)
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');
        my $alt = Zepto::InputParser::has_modifier($event, 'alt');

        if ($ctrl) {
            $self->handle_ctrl_char($char);
        }
        elsif ($alt) {
            $self->handle_alt_char($char);
        }
        else {
            $self->do_insert_char($char);
        }
    }
    elsif ($type eq 'mouse') {
        $self->handle_mouse_event($event);
    }
}

sub handle_ctrl_char {
    my ($self, $char) = @_;

    $char = lc($char);

    # File operations
    if    ($char eq 'n') { $self->cmd_new_file(); }
    elsif ($char eq 'o') { $self->cmd_open_file(); }
    elsif ($char eq 's') { $self->cmd_save(); }
    elsif ($char eq 'w') { $self->cmd_close_tab(); }
    elsif ($char eq 'q') { $self->cmd_quit(); }

    # Edit operations
    elsif ($char eq 'z') { $self->cmd_undo(); }
    elsif ($char eq 'y') { $self->cmd_redo(); }
    elsif ($char eq 'x') { $self->cmd_cut(); }
    elsif ($char eq 'c') { $self->cmd_copy(); }
    elsif ($char eq 'v') { $self->cmd_paste(); }
    elsif ($char eq 'a') { $self->cmd_select_all(); }
    elsif ($char eq 'u') { $self->do_duplicate_line_up(); }
    elsif ($char eq 'd') { $self->do_duplicate_line_down(); }

    # Search operations
    elsif ($char eq 'f') { $self->cmd_find(); }
    elsif ($char eq 'j') { $self->cmd_find_next(); }
    elsif ($char eq 'k') { $self->cmd_find_prev(); }
    elsif ($char eq 'g') { $self->cmd_goto_line(); }
    elsif ($char eq 'e') { $self->cmd_recent_files(); }

    # View
    elsif ($char eq 't') { $self->cmd_toggle_theme(); }
    elsif ($char eq 'p') { $self->cmd_open_file(); }
    elsif ($char eq 'b') { $self->cmd_toggle_tree(); }

    # Comment toggle
    elsif ($char eq '/') { $self->cmd_toggle_comment(); }

    # Command palette
    elsif ($char eq ' ') { $self->cmd_open_palette(); }

    # Reset quit pending for any other command
    $self->{quit_pending} = 0 unless $char eq 'q';
}

sub handle_alt_char {
    my ($self, $char) = @_;

    my $view = $self->active_view();

    # Word movement (Option+Arrow on macOS sends ESC b/f)
    if    ($char eq 'b') { $view->move_word_left(); }
    elsif ($char eq 'f') { $view->move_word_right(); }

    # Inline diff expansion
    elsif ($char eq 'd') { $self->cmd_toggle_diff(); }

    # Column mode toggle
    elsif ($char eq 'c') { $self->cmd_toggle_column_mode(); }

    # Minimap toggle
    elsif ($char eq 'm') { $self->cmd_toggle_minimap(); }

    # Word wrap toggle
    elsif ($char eq 'z') { $self->cmd_toggle_word_wrap(); }

    # Nerd Font toggle
    elsif ($char eq 'i') { $self->cmd_toggle_nerd_font(); }

    # Change navigation
    elsif ($char eq 'n') { $self->cmd_next_change(); }
    elsif ($char eq 'p') { $self->cmd_prev_change(); }

    # Tab navigation (Alt+, prev, Alt+. next)
    elsif ($char eq ',') { $self->cmd_prev_tab(); }
    elsif ($char eq '.') { $self->cmd_next_tab(); }

    # Location history (Alt+- back, Alt+= forward)
    elsif ($char eq '-') { $self->cmd_go_back(); }
    elsif ($char eq '=') { $self->cmd_go_forward(); }

    # Tab switching (Alt+1 through Alt+9)
    elsif ($char ge '1' && $char le '9') {
        $self->cmd_switch_to_tab(ord($char) - ord('1'));  # 0-indexed
    }
}

sub handle_mouse_event {
    my ($self, $event) = @_;

    my $action = $event->{action};
    my $x = $event->{x};
    my $y = $event->{y};
    my $shift = Zepto::InputParser::has_modifier($event, 'shift');
    my $alt = Zepto::InputParser::has_modifier($event, 'alt');

    my $term = $self->{terminal};
    my $view = $self->active_view();

    if ($action eq 'press') {
        # Track mouse button state
        $self->{mouse_button_down} = 1;

        # Check if click is in tab bar (row 1) — but not in tree panel area
        my $_tree_w = 0;
        if ($self->{file_tree} && $self->{prefs}->show_tree()) {
            $_tree_w = $self->{file_tree}->panel_width() + 1;
        }
        if ($y == 1 && $x > $_tree_w) {
            $self->handle_tab_bar_click($x);
            # Start tab drag if we clicked on a tab (not close/scroll buttons)
            my @buttons = Zepto::Renderer->get_tab_bar_buttons();
            for my $btn (@buttons) {
                next unless $btn->{type} eq 'tab';
                if ($x >= $btn->{start} + 1 && $x <= $btn->{end} + 1) {
                    $self->{tab_dragging} = $btn->{index};
                    $self->{tab_drag_start_x} = $x;
                    last;
                }
            }
            return;
        }

        # Ruler bar (row 2) - check for clickable buttons
        if ($y == 2) {
            my @buttons = Zepto::Renderer::get_ruler_buttons();
            for my $btn (@buttons) {
                if ($x >= $btn->{x_start} && $x <= $btn->{x_end}) {
                    if ($btn->{action} eq 'toggle_column_mode') {
                        $self->cmd_toggle_column_mode();
                    }
                    return;
                }
            }
            return;
        }

        # Check if click is on status bar (last row)
        my ($rows, $cols) = $term->get_size();
        if ($y == $rows) {
            if ($self->{state} eq STATE_FIND) {
                $self->handle_find_bar_click($x);
            } elsif ($self->{state} eq STATE_FOOTER_INPUT) {
                $self->_handle_footer_input_click($x);
            } else {
                $self->handle_status_bar_click($x);
            }
            return;
        }

        # Check tree panel region (columns 1..tree_width, rows 1+)
        my $tree_width = 0;
        if ($self->{file_tree} && $self->{prefs}->show_tree()) {
            $tree_width = $self->{file_tree}->panel_width() + 1;
        }
        if ($tree_width > 0 && $x <= $tree_width && $y >= 1 && $y < $rows) {
            if ($x == $tree_width) {
                # Border column — start resize drag
                $self->{tree_border_dragging} = 1;
                return;
            }

            my $tree = $self->{file_tree};
            my $tree_row = $y - 1;
            my $stickies = $tree->sticky_headers();
            my $sticky_count = scalar @$stickies;
            my $search_bar_rows = 1;  # search bar always present

            # Click on search bar (row 0) — focus tree and activate filter
            if ($tree_row == 0) {
                $tree->set_focused(1);
                if (!$tree->filter_active()) {
                    $tree->start_filter();
                }
                return;
            }

            # Check if click is on scrollbar column (rightmost col of panel)
            my $sb = $tree->scrollbar_data();
            my $has_scrollbar = ($sb->{total} > $sb->{visible});
            if ($has_scrollbar && $x == $tree_width - 1) {
                # Start scrollbar drag
                $self->{tree_scrollbar_dragging} = 1;
                $self->_handle_tree_scrollbar_drag($tree_row - $search_bar_rows - $sticky_count, $sb);
                return;
            }

            my $content_row = $tree_row - $search_bar_rows - $sticky_count;
            if ($content_row >= 0) {
                my $flat_idx = $tree->scroll() + $content_row;
                if ($flat_idx < $tree->visible_count()) {
                    $tree->set_cursor($flat_idx);
                    $tree->set_focused(1);
                    my $node = $tree->cursor_node();
                    if ($node) {
                        # Detect double-click (same item within 400ms)
                        my $now = time();
                        my $is_double = (
                            defined $self->{_tree_last_click_idx} &&
                            $self->{_tree_last_click_idx} == $flat_idx &&
                            ($now - ($self->{_tree_last_click_time} // 0)) < 0.4
                        );
                        $self->{_tree_last_click_time} = $now;
                        $self->{_tree_last_click_idx} = $flat_idx;

                        if ($node->{is_dir}) {
                            # Click on dir → toggle expand/collapse
                            $tree->toggle_current();
                        } elsif ($is_double) {
                            # Double-click on file → open and focus document
                            if ($tree->{preview_active}) {
                                $tree->{preview_active} = 0;
                                $tree->{preview_path} = undef;
                                $tree->{pre_preview_tab_index} = undef;
                            } else {
                                $self->_load_file($node->{path});
                            }
                            $tree->set_current_file($node->{path});
                            $tree->set_focused(0);
                        } else {
                            # Single-click on file → preview (like arrow navigation)
                            $self->_tree_preview_current();
                        }
                    }
                }
            }
            return;
        }

        # Click in text area
        my $text_row = $y - 3;  # Adjust for tab bar (1) + ruler bar (2) = text starts at row 3
        my $line_count = $self->active_doc() ? $self->active_doc()->line_count() : 1;
        my $gutter_width = Zepto::Renderer->get_gutter_width($line_count);

        # Check if click is in minimap region (right side)
        my ($rows_size, $cols_size) = $term->get_size();
        my $text_height = $rows_size - RESERVED_ROWS;  # tab + ruler + status
        $text_height = 1 if $text_height < 1;
        my $minimap_width = Zepto::Renderer->get_minimap_width(
            $line_count, $text_height, $cols_size, $gutter_width, $self->{prefs}, $tree_width
        );
        if ($minimap_width > 0 && $x > $cols_size - $minimap_width) {
            $self->{minimap_dragging} = 1;
            $self->_handle_minimap_click($text_row, $text_height);
            return;
        }

        my $visual_col = $x - $tree_width - $gutter_width - 1;  # -1 because terminal columns are 1-indexed

        # Resolve display row to entry via LineMap
        my $line_map = $view->line_map();
        my $entry;
        if ($line_map && $line_map->has_expanded_hunks()) {
            my $scroll_display = $line_map->scroll_display_start($view->scroll_line());
            my $display_row = $scroll_display + $text_row;
            $entry = $line_map->display_entry($display_row);
        }

        # Clicking in the document area (gutter or text) unfocuses tree
        if ($self->{file_tree} && $self->{file_tree}->focused()) {
            $self->_tree_unfocus();
            # Refresh view reference — tab may have changed during unfocus
            $view = $self->active_view();
        }

        # Gutter click: toggle hunk expansion
        if ($visual_col < 0 && $self->active_doc()) {
            my $doc_line;
            my $wm = $view->wrap_map();
            if ($wm) {
                my $scroll_vrow = $view->scroll_visual_row();
                my $target_vrow = $scroll_vrow + $text_row;
                my $seg = $wm->segment_at_visual_row($target_vrow);
                $doc_line = $seg ? $seg->{doc_line} : ($view->scroll_line() + $text_row);
            } elsif ($entry) {
                if ($entry->{type} eq 'old') {
                    # Click on old-line gutter — collapse this hunk
                    if ($line_map && defined $entry->{hunk_idx}) {
                        $line_map->toggle_hunk($entry->{hunk_idx});
                    }
                    return;
                }
                $doc_line = $entry->{line};
            } else {
                $doc_line = $view->scroll_line() + $text_row;
            }

            # Check if this doc line has a VCS marker that can be expanded
            if (defined $doc_line && $doc_line >= 0 && $doc_line < $self->active_doc()->line_count()) {
                my $hunk_idx = $self->active_doc()->vcs_hunk_at_line($doc_line);
                if (defined $hunk_idx) {
                    $self->_ensure_line_map();
                    $line_map = $view->line_map();
                    $line_map->toggle_hunk($hunk_idx);
                    return;
                }
            }
            return;
        }

        if ($visual_col >= 0) {
            # Block clicks on old-line rows (read-only)
            if ($entry && $entry->{type} eq 'old') {
                return;
            }

            my ($doc_line, $doc_col);
            my $wm = $view->wrap_map();
            if ($wm) {
                # Word wrap: convert screen position through WrapMap
                my $scroll_vrow = $view->scroll_visual_row();
                my $target_vrow = $scroll_vrow + $text_row;
                ($doc_line, $doc_col) = $wm->visual_to_doc($target_vrow, $visual_col);
            } else {
                if ($entry) {
                    $doc_line = $entry->{line};
                } else {
                    $doc_line = $view->scroll_line() + $text_row;
                }

                # Clamp line to document bounds
                $doc_line = 0 if $doc_line < 0;
                $doc_line = $self->active_doc()->line_count() - 1
                    if $doc_line >= $self->active_doc()->line_count();

                # Convert visual column to document column, accounting for tabs
                # Need to add scroll_col to visual position first
                my $absolute_visual_col = $view->scroll_col() + $visual_col;
                my $line_content = $self->active_doc()->get_line($doc_line) // '';
                $doc_col = Zepto::Renderer::visual_to_char_col($line_content, $absolute_visual_col);
            }

            if ($alt) {
                # Alt+Click: start column selection at click position.
                # We set column_select=1 before positioning so the cursor
                # can land past short line ends (virtual whitespace).
                $view->clear_selection();
                $view->{column_select} = 1;
                # Clamp line only (col allowed past end in column mode)
                my $max_line = $self->active_doc()->line_count() - 1;
                $doc_line = 0 if $doc_line < 0;
                $doc_line = $max_line if $doc_line > $max_line;
                $doc_col = 0 if $doc_col < 0;
                $view->{cursor_line} = $doc_line;
                $view->{cursor_col} = $doc_col;
                $view->{_preferred_col} = $doc_col;
                $view->start_column_selection();
                $view->ensure_cursor_visible();
            } elsif ($shift && $view->column_select()) {
                # Shift+Click with column mode: extend column selection
                $view->set_cursor($doc_line, $doc_col, 1);
            } else {
                # Multi-click detection: double-click = word, triple-click = line
                my $now = time();
                my $click_count = 1;
                if (defined $self->{_last_click_time} &&
                    ($now - $self->{_last_click_time}) < 0.4 &&
                    defined $self->{_last_click_line} &&
                    $self->{_last_click_line} == $doc_line) {
                    $click_count = ($self->{_last_click_count} || 1) + 1;
                    $click_count = 1 if $click_count > 3;  # cycle back after triple
                }
                $self->{_last_click_time} = $now;
                $self->{_last_click_line} = $doc_line;
                $self->{_last_click_count} = $click_count;

                if ($click_count == 2) {
                    # Double-click: select word
                    $view->set_cursor($doc_line, $doc_col, $shift);
                    $view->select_word();
                } elsif ($click_count == 3) {
                    # Triple-click: select line
                    $view->set_cursor($doc_line, $doc_col, 0);
                    $view->select_line();
                } else {
                    $view->set_cursor($doc_line, $doc_col, $shift);
                }
            }
        }
    }
    elsif ($action eq 'release') {
        # Track mouse button state
        $self->{mouse_button_down} = 0;
        $self->{minimap_dragging} = 0;
        $self->{tree_border_dragging} = 0;
        $self->{tree_scrollbar_dragging} = 0;
        $self->{tab_dragging} = undef;
        # End any input widget drag
        $self->{find_widget}->handle_mouse_drag_end()         if $self->{find_widget};
        $self->{find_replace_widget}->handle_mouse_drag_end() if $self->{find_replace_widget};
        if ($self->{footer_input} && $self->{footer_input}{widget}) {
            $self->{footer_input}{widget}->handle_mouse_drag_end();
        }
    }
    elsif ($action eq 'scroll') {
        # Scroll on tab bar — cycle through tabs
        if ($y == 2) {
            if ($event->{button} eq 'up') {
                $self->cmd_prev_tab();
            } else {
                $self->cmd_next_tab();
            }
            return;
        }

        # Scroll in tree panel
        my $tw = 0;
        if ($self->{file_tree} && $self->{prefs}->show_tree()) {
            $tw = $self->{file_tree}->panel_width() + 1;
        }
        if ($tw > 0 && $x <= $tw && $y >= 4) {
            if ($event->{button} eq 'up') {
                $self->{file_tree}->move_up();
            } else {
                $self->{file_tree}->move_down();
            }
            return;
        }

        # Scroll viewport without moving cursor — 1 line per event for smooth feel
        if ($event->{button} eq 'up') {
            $view->scroll_up(1);
        }
        else {
            $view->scroll_down(1);
        }
    }
    elsif ($action eq 'drag') {
        # Only handle drag if mouse button is actually down
        # (some terminals send spurious motion events)
        return unless $self->{mouse_button_down};

        # Drag in status-bar input widgets (find bar / footer input)
        my ($rows_d, $cols_d) = $term->get_size();
        if ($y == $rows_d) {
            if ($self->{state} eq STATE_FIND) {
                $self->_handle_find_bar_drag($x);
                return;
            } elsif ($self->{state} eq STATE_FOOTER_INPUT) {
                $self->_handle_footer_input_drag($x);
                return;
            }
        }

        # Handle tab drag reorder
        if (defined $self->{tab_dragging}) {
            $self->_handle_tab_drag($x, $y);
            return;
        }

        # Handle tree border drag (resize)
        if ($self->{tree_border_dragging} && $self->{file_tree}) {
            $self->{file_tree}->set_width($x - 1);
            return;
        }

        # Handle tree scrollbar drag
        if ($self->{tree_scrollbar_dragging} && $self->{file_tree}) {
            my $tree = $self->{file_tree};
            my $tree_row = $y - 1;
            my $stickies = $tree->sticky_headers();
            my $sticky_count = scalar @$stickies;
            my $filter_rows = $tree->filter_active() ? 1 : 0;
            my $sb = $tree->scrollbar_data();
            $self->_handle_tree_scrollbar_drag($tree_row - $sticky_count - $filter_rows, $sb);
            return;
        }

        # Handle minimap drag (scrollbar behavior)
        if ($self->{minimap_dragging}) {
            my $text_row = $y - 3;
            my ($rows_size, $cols_size) = $term->get_size();
            my $text_height = $rows_size - RESERVED_ROWS;
            $text_height = 1 if $text_height < 1;
            $self->_handle_minimap_click($text_row, $text_height);
            return;
        }

        # Handle drag for selection
        my $text_row = $y - 3;  # Adjust for tab bar (1) + ruler bar (2) = text starts at row 3
        my $line_count = $self->active_doc() ? $self->active_doc()->line_count() : 1;
        my $gutter_width = Zepto::Renderer->get_gutter_width($line_count);
        my $drag_tree_w = 0;
        if ($self->{file_tree} && $self->{prefs}->show_tree()) {
            $drag_tree_w = $self->{file_tree}->panel_width() + 1;
        }
        my $visual_col = $x - $drag_tree_w - $gutter_width - 1;  # -1 because terminal columns are 1-indexed

        # Resolve display row to document coordinates
        my ($doc_line, $doc_col);
        my $wm = $view->wrap_map();
        if ($wm) {
            # Word wrap: convert screen position through WrapMap
            my $scroll_vrow = $view->scroll_visual_row();
            my $target_vrow = $scroll_vrow + $text_row;
            ($doc_line, $doc_col) = $wm->visual_to_doc($target_vrow, $visual_col);
        } else {
            my $line_map = $view->line_map();
            if ($line_map && $line_map->has_expanded_hunks()) {
                my $scroll_display = $line_map->scroll_display_start($view->scroll_line());
                my $display_row = $scroll_display + $text_row;
                my $drag_entry = $line_map->display_entry($display_row);
                return if !$drag_entry || $drag_entry->{type} eq 'old';
                $doc_line = $drag_entry->{line};
            } else {
                $doc_line = $view->scroll_line() + $text_row;
            }

            # Clamp line to document bounds
            $doc_line = 0 if $doc_line < 0;
            $doc_line = $self->active_doc()->line_count() - 1
                if $doc_line >= $self->active_doc()->line_count();

            # Convert visual column to document column, accounting for tabs
            my $absolute_visual_col = $view->scroll_col() + $visual_col;
            my $line_content = $self->active_doc()->get_line($doc_line) // '';
            $doc_col = Zepto::Renderer::visual_to_char_col($line_content, $absolute_visual_col);
        }

        if ($visual_col >= 0 && !$view->has_selection()) {
            # Start selection on first drag
            if ($alt || $view->column_select()) {
                $view->start_column_selection() unless $view->column_select();
                # In column mode, set anchor at current cursor before extending
                $view->_start_selection_if_needed();
            } else {
                $view->set_cursor($view->cursor_line(), $view->cursor_col(), 1);
            }
        }

        # Extend selection (column or linear)
        if ($visual_col >= 0) {
            if ($alt && !$view->column_select()) {
                $view->start_column_selection();
            }
            $view->set_cursor($doc_line, $doc_col, 1);
        }
    }
}

# =============================================================================
# Tab bar click handling
# =============================================================================

sub handle_tab_bar_click {
    my ($self, $x) = @_;

    # Clicking the tab bar always returns focus from file tree to editor
    if ($self->{file_tree} && $self->{file_tree}->focused()) {
        my $tree = $self->{file_tree};
        # Close transient preview tab created by tree navigation
        if ($tree->{preview_active} && !$tree->{_preview_is_existing_tab}) {
            $self->_close_preview_tab();
        }
        $tree->{preview_active} = 0;
        $tree->{preview_path} = undef;
        $tree->{pre_preview_tab_index} = undef;
        $tree->set_focused(0);
    }

    my @buttons = Zepto::Renderer->get_tab_bar_buttons();

    # Check scroll arrows first
    for my $btn (@buttons) {
        next unless $btn->{type} eq 'scroll_left' || $btn->{type} eq 'scroll_right';
        if ($x >= $btn->{start} + 1 && $x <= $btn->{end} + 1) {
            if ($btn->{type} eq 'scroll_left') {
                $self->cmd_prev_tab();
            } else {
                $self->cmd_next_tab();
            }
            return;
        }
    }

    # Check close buttons (they overlap tab regions)
    for my $btn (@buttons) {
        next unless $btn->{type} eq 'close';
        if ($x >= $btn->{start} + 1 && $x <= $btn->{end} + 1) {  # +1 for 1-indexed terminal x
            # Switch to this tab first, then close it
            $self->_switch_to_tab($btn->{index});
            $self->cmd_close_tab();
            return;
        }
    }

    # Then check tab regions
    for my $btn (@buttons) {
        next unless $btn->{type} eq 'tab';
        if ($x >= $btn->{start} + 1 && $x <= $btn->{end} + 1) {  # +1 for 1-indexed terminal x
            $self->_switch_to_tab($btn->{index});
            return;
        }
    }
}

# Handle tab drag reorder: find which tab position the cursor is over
# and move the dragged tab there.
sub _handle_tab_drag {
    my ($self, $x, $y) = @_;

    # Only reorder while dragging on the tab bar row
    return unless $y == 2;

    my $from = $self->{tab_dragging};
    my $tm = $self->{tab_manager};
    return unless defined $from && $from >= 0 && $from < $tm->tab_count();

    # Hit-test against tab button midpoints to find the drop target
    my @buttons = Zepto::Renderer->get_tab_bar_buttons();
    my $to;
    for my $btn (@buttons) {
        next unless $btn->{type} eq 'tab';
        my $mid = ($btn->{start} + $btn->{end}) / 2 + 1;  # +1 for 1-indexed
        if ($x <= $mid) {
            $to = $btn->{index};
            last;
        }
        $to = $btn->{index};  # past this tab's midpoint, candidate is here
    }

    return unless defined $to;
    if ($to != $from) {
        $tm->move_tab($from, $to);
        $self->{tab_dragging} = $to;  # Follow the moved tab
    }
}

# =============================================================================
# Minimap click handling
# =============================================================================

# Handle a click or drag in the minimap region.
# Jumps cursor to the corresponding document line and centers the viewport.
sub _handle_minimap_click {
    my ($self, $text_row, $text_height) = @_;

    return unless $self->active_doc();

    # Clamp text_row to valid range
    $text_row = 0 if $text_row < 0;
    $text_row = $text_height - 1 if $text_row >= $text_height;

    my $total_lines = $self->active_doc()->line_count();
    my $view = $self->active_view();
    my $viewport_rows = $view->viewport_rows();

    # Map minimap row to document line proportionally
    my $ratio = $text_height > 1 ? $text_row / ($text_height - 1) : 0;
    my $target_line = int($ratio * ($total_lines - 1) + 0.5);
    $target_line = 0 if $target_line < 0;
    $target_line = $total_lines - 1 if $target_line >= $total_lines;

    # Move cursor to the target line (column 0)
    $view->set_cursor($target_line, 0);

    # Center the viewport on the target line
    my $new_scroll = $target_line - int($viewport_rows / 2);
    my $max_scroll = $total_lines - $viewport_rows;
    $max_scroll = 0 if $max_scroll < 0;
    $new_scroll = 0 if $new_scroll < 0;
    $new_scroll = $max_scroll if $new_scroll > $max_scroll;

    $view->{scroll_line} = $new_scroll;
}

# =============================================================================
# Dialog Handling
# =============================================================================

sub open_dialog {
    my ($self, %opts) = @_;
    $self->{state} = STATE_DIALOG;
    $self->{dialog} = {
        title   => $opts{title} // 'Dialog',
        prompt  => $opts{prompt} // '',
        value   => $opts{value} // '',
        cursor  => length($opts{value} // ''),
        on_submit => $opts{on_submit},
        on_cancel => $opts{on_cancel},
    };
}

sub close_dialog {
    my ($self) = @_;
    $self->{state} = STATE_EDITING;
    $self->{dialog} = undef;
}

sub handle_dialog_event {
    my ($self, $event) = @_;

    my $dialog = $self->{dialog};
    my $type = $event->{type};

    if ($type eq 'key') {
        my $key = $event->{key};

        if ($key eq 'enter') {
            my $value = $dialog->{value};
            $self->close_dialog();
            $dialog->{on_submit}->($value) if $dialog->{on_submit};
        }
        elsif ($key eq 'escape') {
            $self->close_dialog();
            $dialog->{on_cancel}->() if $dialog->{on_cancel};
        }
        elsif ($key eq 'backspace') {
            if ($dialog->{cursor} > 0) {
                my $val = $dialog->{value};
                my $pos = $dialog->{cursor};
                $dialog->{value} = substr($val, 0, $pos - 1) . substr($val, $pos);
                $dialog->{cursor}--;
            }
        }
        elsif ($key eq 'delete') {
            if ($dialog->{cursor} < length($dialog->{value})) {
                my $val = $dialog->{value};
                my $pos = $dialog->{cursor};
                $dialog->{value} = substr($val, 0, $pos) . substr($val, $pos + 1);
            }
        }
        elsif ($key eq 'left') {
            $dialog->{cursor}-- if $dialog->{cursor} > 0;
        }
        elsif ($key eq 'right') {
            $dialog->{cursor}++ if $dialog->{cursor} < length($dialog->{value});
        }
        elsif ($key eq 'home') {
            $dialog->{cursor} = 0;
        }
        elsif ($key eq 'end') {
            $dialog->{cursor} = length($dialog->{value});
        }
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        unless (Zepto::InputParser::has_modifier($event, 'ctrl')) {
            my $val = $dialog->{value};
            my $pos = $dialog->{cursor};
            $dialog->{value} = substr($val, 0, $pos) . $char . substr($val, $pos);
            $dialog->{cursor}++;
        }
    }
}

# =============================================================================
# Prompt Handling (status bar choices)
# =============================================================================

sub open_prompt {
    my ($self, %opts) = @_;
    $self->{state} = STATE_PROMPT;
    $self->{prompt} = {
        text    => $opts{text} // '',
        options => $opts{options} // [],  # [{key => 's', label => 'Save'}, ...]
        on_select => $opts{on_select},
    };
}

sub close_prompt {
    my ($self) = @_;
    $self->{state} = STATE_EDITING;
    $self->{prompt} = undef;
}

sub handle_prompt_event {
    my ($self, $event) = @_;

    my $prompt = $self->{prompt};
    my $type = $event->{type};

    if ($type eq 'key') {
        my $key = $event->{key};
        if ($key eq 'escape') {
            $self->close_prompt();
            return;
        }
    }
    elsif ($type eq 'char') {
        my $char = lc($event->{char});

        # Check if char matches an option
        for my $opt (@{$prompt->{options}}) {
            if (lc($opt->{key}) eq $char) {
                $self->close_prompt();
                $prompt->{on_select}->($opt->{key}) if $prompt->{on_select};
                return;
            }
        }
    }
    elsif ($type eq 'mouse' && $event->{action} eq 'press') {
        # Check for clicks on options in status bar
        # Options are rendered with positions stored by renderer
        my @buttons = Zepto::Renderer::get_prompt_buttons();
        for my $btn (@buttons) {
            if ($event->{y} == $btn->{y} &&
                $event->{x} >= $btn->{x_start} && $event->{x} <= $btn->{x_end}) {
                $self->close_prompt();
                $prompt->{on_select}->($btn->{key}) if $prompt->{on_select};
                return;
            }
        }
    }
}

# =============================================================================
# Footer Input Handling (text input in status bar)
# =============================================================================

sub open_footer_input {
    my ($self, %opts) = @_;
    $self->{state} = STATE_FOOTER_INPUT;
    my $widget = Zepto::InputWidget->new(value => $opts{value} // '');
    if ($opts{select_all} && length($opts{value} // '')) {
        $widget->{sel_start} = 0;
        $widget->{sel_end}   = length($opts{value});
    }
    $self->{footer_input} = {
        id        => $opts{id},
        prompt    => $opts{prompt} // '',
        widget    => $widget,
        hint      => $opts{hint},
        on_submit => $opts{on_submit},
        on_cancel => $opts{on_cancel},
    };
}

sub close_footer_input {
    my ($self) = @_;
    $self->{state} = STATE_EDITING;
    $self->{footer_input} = undef;
}

sub handle_footer_input_event {
    my ($self, $event) = @_;

    my $input  = $self->{footer_input};
    my $widget = $input->{widget};
    my $type   = $event->{type};

    if ($type eq 'key') {
        my $key = $event->{key};
        if ($key eq 'enter') {
            my $value    = $widget->value();
            my $callback = $input->{on_submit};
            $self->close_footer_input();
            $callback->($value) if $callback;
        }
        elsif ($key eq 'escape') {
            my $callback = $input->{on_cancel};
            $self->close_footer_input();
            $callback->() if $callback;
        }
        else {
            $widget->handle_event($event, \$self->{clipboard});
        }
    }
    elsif ($type eq 'char') {
        $widget->handle_event($event, \$self->{clipboard});
    }
}

# =============================================================================
# Incremental Find Handling
# =============================================================================

sub enter_find_mode {
    my ($self) = @_;
    # Column selection is incompatible with find mode — clear it
    my $view = $self->active_view();
    if ($view && $view->column_select()) {
        $view->clear_selection();
    }
    $self->{state} = STATE_FIND;
    $self->{find_widget}         = Zepto::InputWidget->new(value => $self->{search_term});
    $self->{find_replace_widget} = Zepto::InputWidget->new(value => $self->{search_replace});
    $self->{find_replace_active} = 1;  # Always show replace field
    $self->{find_focus} = 'find';
    $self->{find_replace_preview} = undef;  # Virtual preview data
    $self->{find_replaced} = [];      # Clear replaced highlights
    $self->_update_find_matches();
}

sub exit_find_mode {
    my ($self, $keep_changes) = @_;

    my $engine = $self->active_find_engine();

    # If keeping changes and we have matches to replace, apply them now
    if ($keep_changes && $self->{find_replace_active} && $self->{find_replace_all}) {
        # Complete background search first to get all matches
        while ($engine->is_searching) {
            $engine->tick(100);  # Finish quickly
        }

        # Use the optimized replace function
        $self->{find_matches} = $engine->all_matches();
        $self->_replace_all() if @{$self->{find_matches}};
    }

    # Abort any background search
    $engine->abort() if $engine;

    $self->{search_term}    = $self->{find_widget}->value();         # Save for next time
    $self->{search_replace} = $self->{find_replace_widget}->value(); # Save replace too
    $self->{find_matches} = [];  # Clear highlights
    $self->{find_replaced} = [];  # Clear replaced highlights
    $self->{find_replace_preview} = undef;  # Clear virtual preview
    $self->{find_replace_active} = 0;
    $self->{state} = STATE_EDITING;
}

sub handle_find_event {
    my ($self, $event) = @_;

    my $type = $event->{type};

    # Determine which widget has focus
    my $in_replace = $self->{find_replace_active} && $self->{find_focus} eq 'replace';
    my $widget = $in_replace ? $self->{find_replace_widget} : $self->{find_widget};

    if ($type eq 'key') {
        my $key   = $event->{key};
        my $shift = Zepto::InputParser::has_modifier($event, 'shift');

        if ($key eq 'enter') {
            if ($self->{find_replace_active}) {
                if ($self->{find_replace_all}) {
                    # In replace-all mode, Enter confirms and exits
                    $self->exit_find_mode(1);
                } else {
                    # In replace-one mode, Enter replaces current and moves to next
                    $self->_replace_current() if @{$self->{find_matches}};
                }
            } else {
                # Exit find mode, keep cursor at current match
                $self->exit_find_mode(1);
            }
        }
        elsif ($key eq 'escape') {
            # Exit find mode, undo preview if any
            $self->exit_find_mode(0);
        }
        elsif ($key eq 'up') {
            # Navigate to previous match
            $self->_find_navigate(-1);
        }
        elsif ($key eq 'down') {
            # Navigate to next match
            $self->_find_navigate(1);
        }
        elsif ($key eq 'tab') {
            if ($shift) {
                # Shift+Tab: cycle through modes/toggles
                # replace-all -> replace-one -> regex -> case -> replace-all
                if ($self->{find_replace_active} && $self->{find_replace_all}) {
                    $self->{find_replace_all} = 0;
                } elsif ($self->{find_replace_active} && !$self->{find_replace_all}) {
                    $self->{find_replace_all} = 1;
                    if ($self->{find_regex}) {
                        $self->{find_regex} = 0;
                        $self->{find_case} = 1;
                    } elsif ($self->{find_case}) {
                        $self->{find_case} = 0;
                    } else {
                        $self->{find_regex} = 1;
                    }
                    $self->_apply_replace_preview();
                } else {
                    # No replace active, just cycle regex/case
                    if ($self->{find_regex}) {
                        $self->{find_regex} = 0;
                        $self->{find_case} = 1;
                    } elsif ($self->{find_case}) {
                        $self->{find_case} = 0;
                    } else {
                        $self->{find_regex} = 1;
                    }
                }
                $self->_update_find_matches(1);  # Skip jump when toggling options
            } else {
                # Tab: toggle between find/replace fields, or show replace
                if (!$self->{find_replace_active}) {
                    # Show replace field, prepopulate with find string
                    $self->{find_replace_active} = 1;
                    $self->{find_focus} = 'replace';
                    $self->{find_replace_widget}->set_value($self->{find_widget}->value());
                } elsif ($self->{find_focus} eq 'find') {
                    $self->{find_focus} = 'replace';
                } else {
                    $self->{find_focus} = 'find';
                }
            }
        }
        else {
            # Delegate cursor/editing keys to widget; trigger side effects on value change
            my $old_find    = $self->{find_widget}->value();
            my $old_replace = $self->{find_replace_widget}->value();
            $widget->handle_event($event, \$self->{clipboard});
            $self->_find_value_changed($in_replace, $old_find, $old_replace);
        }
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');

        if ($ctrl && lc($char) eq 'r') {
            # Ctrl+R: Toggle regex mode (find-specific, not standard editing)
            $self->{find_regex} = !$self->{find_regex};
            $self->_reset_replace_preview();
            $self->_update_find_matches(1);
        }
        elsif ($ctrl && lc($char) eq 'c') {
            # Ctrl+C: Toggle case-sensitive mode (find-specific, overrides copy)
            $self->{find_case} = !$self->{find_case};
            $self->_reset_replace_preview();
            $self->_update_find_matches(1);
        }
        else {
            # Delegate all other chars to widget (including ctrl+a, ctrl+x, ctrl+v)
            my $old_find    = $self->{find_widget}->value();
            my $old_replace = $self->{find_replace_widget}->value();
            $widget->handle_event($event, \$self->{clipboard});
            $self->_find_value_changed($in_replace, $old_find, $old_replace);
        }
    }
}

# Trigger find/replace side effects after widget edits.
sub _find_value_changed {
    my ($self, $in_replace, $old_find, $old_replace) = @_;
    if ($in_replace) {
        if ($self->{find_replace_widget}->value() ne $old_replace) {
            $self->_apply_replace_preview() if $self->{find_replace_all};
        }
    } else {
        if ($self->{find_widget}->value() ne $old_find) {
            $self->_reset_replace_preview();
            $self->_update_find_matches(1);
        }
    }
}

# Handle clicks on the find bar (status bar in find mode)
sub handle_find_bar_click {
    my ($self, $x) = @_;

    # Compute click regions based on current state (must match _render_find_bar layout)
    my ($rows, $cols) = $self->{terminal}->get_size();

    # Calculate match text width
    my $match_count = $self->active_find_engine() ? $self->active_find_engine()->match_count() : 0;
    my $current = $self->{find_current} // 0;
    my $match_text = $match_count == 0
        ? (length($self->{find_widget}->value()) ? 'No matches' : '')
        : (($current + 1) . ' of ' . $match_count);
    my $match_text_len = length($match_text);

    # Right side width (same formula as renderer)
    my $right_side_width = 45 + $match_text_len;

    # Input field width (same formula as renderer)
    my $available = $cols - 2 - 5 - 1 - 8 - 1 - $right_side_width;  # " Find:" + "Replace:" + spaces
    my $input_width = int($available / 2);
    $input_width = 8 if $input_width < 8;
    $input_width = 40 if $input_width > 40;

    # Click region positions (1-indexed, matching renderer)
    my $pos = 1;  # Leading space
    $pos++;
    my $find_start = $pos + 5;  # After "Find:"
    my $find_end = $find_start + $input_width - 1;
    my $replace_start = $find_end + 1 + 1 + 8;  # space + "Replace:"
    my $replace_end = $replace_start + $input_width - 1;

    # Check which region was clicked
    if ($x >= $find_start && $x <= $find_end) {
        $self->{find_focus} = 'find';
        my $char_offset = $x - $find_start;
        $self->{find_widget}->handle_mouse_click($char_offset);
    }
    elsif ($x >= $replace_start && $x <= $replace_end) {
        $self->{find_focus} = 'replace';
        my $char_offset = $x - $replace_start;
        $self->{find_replace_widget}->handle_mouse_click($char_offset);
    }
    else {
        # For buttons on the right side, scan from the right
        # Layout after replace field: " " + ".* ^R" + " " + "Aa ^C" + " " + "X Esc" + " " + "✓ Enter"
        # Pill widths: regex = 9, case = 9, cancel = 9, ok = 11
        my $button_start = $replace_end + 2;  # space after replace field

        my $regex_start = $button_start;
        my $regex_end = $regex_start + 8;  # 9 chars

        my $case_start = $regex_end + 2;  # space between
        my $case_end = $case_start + 8;  # 9 chars

        my $cancel_start = $case_end + 2;  # space between
        my $cancel_end = $cancel_start + 8;  # 9 chars

        my $ok_start = $cancel_end + 2;  # space
        my $ok_end = $ok_start + 10;  # 11 chars

        if ($x >= $regex_start && $x <= $regex_end) {
            $self->{find_regex} = !$self->{find_regex};
            $self->_reset_replace_preview();
            $self->_update_find_matches(1);
        }
        elsif ($x >= $case_start && $x <= $case_end) {
            $self->{find_case} = !$self->{find_case};
            $self->_reset_replace_preview();
            $self->_update_find_matches(1);
        }
        elsif ($x >= $cancel_start && $x <= $cancel_end) {
            $self->exit_find_mode(0);
        }
        elsif ($x >= $ok_start && $x <= $ok_end) {
            $self->exit_find_mode(1);
        }
    }
}

# Drag within find bar: extend selection on the focused widget.
sub _handle_find_bar_drag {
    my ($self, $x) = @_;
    my ($rows, $cols) = $self->{terminal}->get_size();

    # Recompute field positions (same as handle_find_bar_click)
    my $match_count = $self->active_find_engine() ? $self->active_find_engine()->match_count() : 0;
    my $match_text  = $match_count == 0
        ? (length($self->{find_widget}->value()) ? 'No matches' : '')
        : (($self->{find_current} // 0) + 1) . ' of ' . $match_count;
    my $right_side_width = 45 + length($match_text);
    my $available   = $cols - 2 - 5 - 1 - 8 - 1 - $right_side_width;
    my $input_width = int($available / 2);
    $input_width = 8  if $input_width < 8;
    $input_width = 40 if $input_width > 40;

    my $find_start    = 7;  # " " + " Find:" = 7
    my $find_end      = $find_start + $input_width - 1;
    my $replace_start = $find_end + 1 + 1 + 8;
    my $replace_end   = $replace_start + $input_width - 1;

    my $in_replace = $self->{find_replace_active} && $self->{find_focus} eq 'replace';
    if ($in_replace && $x >= $replace_start && $x <= $replace_end) {
        $self->{find_replace_widget}->handle_mouse_drag_update($x - $replace_start);
    } elsif (!$in_replace && $x >= $find_start && $x <= $find_end) {
        $self->{find_widget}->handle_mouse_drag_update($x - $find_start);
    }
}

# Click within footer input field: place cursor.
sub _handle_footer_input_click {
    my ($self, $x) = @_;
    my $input = $self->{footer_input};
    return unless $input && $input->{widget};
    # Field starts right after " Prompt: " — prompt_len includes the two surrounding spaces
    my $prompt_len = length($input->{prompt} // '') + 2;
    my $char_offset = $x - $prompt_len - 1;  # -1: terminal columns are 1-indexed
    $input->{widget}->handle_mouse_click($char_offset);
}

# Drag within footer input field: extend selection.
sub _handle_footer_input_drag {
    my ($self, $x) = @_;
    my $input = $self->{footer_input};
    return unless $input && $input->{widget};
    my $prompt_len  = length($input->{prompt} // '') + 2;
    my $char_offset = $x - $prompt_len - 1;
    $input->{widget}->handle_mouse_drag_update($char_offset);
}

# Reset replace preview state when find term changes
sub _reset_replace_preview {
    my ($self) = @_;

    # Clear virtual preview state (no buffer modification to undo!)
    $self->{find_replace_preview} = undef;
    $self->{find_replaced} = [];
}


sub _update_find_matches {
    my ($self, $skip_jump) = @_;
    my $doc = $self->active_doc();
    my $term = $self->{find_widget}->value();
    my $view = $self->active_view();
    my $engine = $self->active_find_engine();

    # Empty search = no matches
    if (!length($term)) {
        $self->{find_matches} = [];
        $self->{find_current} = 0;
        return;
    }

    # Get viewport bounds
    my $viewport_start = $view->scroll_line();
    my $viewport_end = $viewport_start + $view->viewport_rows();

    # Use FindEngine for viewport-first search
    # This returns viewport matches synchronously (<5ms)
    # and starts background search for the rest
    my $viewport_matches = $engine->search(
        $term,
        $viewport_start,
        $viewport_end,
        case_sensitive => $self->{find_case},
        use_regex      => $self->{find_regex},
    );

    # Get all available matches (viewport + any completed background)
    # Note: if background search is still running, this returns partial results
    $self->{find_matches} = $engine->matches();

    $self->_find_nearest_match() unless $skip_jump;
}

sub _find_nearest_match {
    my ($self) = @_;

    my $matches = $self->{find_matches};
    return unless @$matches;

    # Get current cursor position (line/col)
    my $view = $self->active_view();
    my $cursor_line = $view->cursor_line();
    my $cursor_col = $view->cursor_col();

    # Find the match nearest to cursor (prefer match at or after cursor)
    my $nearest_idx = 0;

    # Helper to compare positions: returns -1 if a < cursor, 0 if equal, 1 if > cursor
    my $cmp_to_cursor = sub {
        my ($m) = @_;
        return $m->{line} <=> $cursor_line || $m->{col} <=> $cursor_col;
    };

    # Helper to compute "distance" (simple line+col diff)
    my $dist = sub {
        my ($m) = @_;
        return abs($m->{line} - $cursor_line) * 10000 + abs($m->{col} - $cursor_col);
    };

    my $nearest_cmp = $cmp_to_cursor->($matches->[0]);
    my $nearest_dist = $dist->($matches->[0]);

    for my $i (1 .. $#$matches) {
        my $m = $matches->[$i];
        my $m_cmp = $cmp_to_cursor->($m);
        my $m_dist = $dist->($m);

        # Prefer matches at or after cursor
        if ($m_cmp >= 0 && $nearest_cmp < 0) {
            $nearest_idx = $i;
            $nearest_cmp = $m_cmp;
            $nearest_dist = $m_dist;
        } elsif (($m_cmp >= 0) == ($nearest_cmp >= 0)) {
            if ($m_dist < $nearest_dist) {
                $nearest_idx = $i;
                $nearest_cmp = $m_cmp;
                $nearest_dist = $m_dist;
            }
        }
    }

    $self->{find_current} = $nearest_idx;
    $self->_jump_to_match($nearest_idx);
}

sub _find_navigate {
    my ($self, $direction) = @_;

    # Get latest matches from engine (includes completed background results)
    my $engine = $self->active_find_engine();
    if ($engine) {
        $self->{find_matches} = $engine->matches();
    }

    my $matches = $self->{find_matches};
    return unless @$matches;

    my $new_idx = $self->{find_current} + $direction;

    # Wrap around
    if ($new_idx < 0) {
        $new_idx = $#$matches;
    } elsif ($new_idx > $#$matches) {
        $new_idx = 0;
    }

    $self->{find_current} = $new_idx;
    $self->_jump_to_match($new_idx);
}

sub _jump_to_match {
    my ($self, $idx) = @_;

    my $matches = $self->{find_matches};
    return unless $idx >= 0 && $idx < @$matches;

    my $match = $matches->[$idx];
    my $view = $self->active_view();

    # Use line/col directly from FindEngine match
    my $line = $match->{line};
    my $col = $match->{col};

    # Move cursor and select the match
    $view->clear_selection();
    $view->set_cursor($line, $col);
    $view->set_cursor($line, $col + $match->{length}, 1);  # extend selection

    # Ensure match is visible
    $view->ensure_cursor_visible();
}

sub _replace_current {
    my ($self) = @_;

    my $matches = $self->{find_matches};
    return unless @$matches;

    my $idx = $self->{find_current};
    return unless $idx >= 0 && $idx < @$matches;

    my $match = $matches->[$idx];
    my $doc = $self->active_doc();
    my $replacement = $self->{find_replace_widget}->value();

    # Expand capture references ($0, $1, ...) if in regex mode
    my $engine = $self->active_find_engine();
    my $expanded = $engine->expand_replacement_for_match($match, $replacement);

    # Convert line/col to byte offset for document operations
    my $offset = $doc->line_col_to_offset($match->{line}, $match->{col});

    # Replace the match in the document
    $doc->replace($offset, $offset + $match->{length}, $expanded);

    # Update matches after replacement
    $self->_update_find_matches();

    # Navigate to next match (or stay at same index if matches remain)
    if (@{$self->{find_matches}}) {
        # Clamp to valid range
        $self->{find_current} = 0 if $self->{find_current} >= @{$self->{find_matches}};
        $self->_jump_to_match($self->{find_current});
    }
}

sub _replace_all {
    my ($self) = @_;

    my $matches = $self->{find_matches};
    return unless @$matches;

    my $doc = $self->active_doc();
    my $replacement = $self->{find_replace_widget}->value();
    my $total = scalar @$matches;

    # For small numbers of matches, do it synchronously
    if ($total <= 100) {
        $self->_replace_all_sync();
        return;
    }

    # Set up progress state and show initial UI
    $self->{_replace_active} = 1;
    $self->{_replace_total} = $total;
    $self->{_replace_progress} = 0;
    $self->render();

    # Get full text and build line offset cache (much faster than repeated API calls)
    my $text = $doc->text();
    my @line_offsets = (0);  # Line 0 starts at offset 0
    my $pos = 0;
    while (($pos = index($text, "\n", $pos)) >= 0) {
        push @line_offsets, $pos + 1;  # Next line starts after newline
        $pos++;
    }

    # Convert matches to offsets using cache (fast)
    my @offsets;
    for my $m (@$matches) {
        my $line_start = $line_offsets[$m->{line}] // 0;
        push @offsets, {
            offset => $line_start + $m->{col},
            length => $m->{length},
        };
    }

    # Sort by offset ascending to build new string left-to-right
    @offsets = sort { $a->{offset} <=> $b->{offset} } @offsets;

    # Build new string by concatenating: non-match regions + replacements
    # This is O(n) vs O(n*k) for in-place substr modifications
    my $engine = $self->active_find_engine();
    my $re = $engine->_build_regex($self->{find_widget}->value());
    my $has_captures = $self->{find_regex} && $replacement =~ /\$/;

    my $result = '';
    my $last_end = 0;
    for my $m (@offsets) {
        # Add text between last match and this one
        $result .= substr($text, $last_end, $m->{offset} - $last_end);
        # Add replacement, expanding capture refs if needed
        if ($has_captures && $re) {
            my $matched_text = substr($text, $m->{offset}, $m->{length});
            $result .= $engine->expand_replacement_for_text($matched_text, $replacement, $re);
        } else {
            $result .= $replacement;
        }
        $last_end = $m->{offset} + $m->{length};
    }
    # Add remaining text after last match
    $result .= substr($text, $last_end);
    $text = $result;

    # Replace entire document content in one operation
    $doc->replace(0, $doc->length(), $text);

    # Clear progress state
    $self->{_replace_active} = 0;

    # Update matches (should be empty after replace all)
    $self->_update_find_matches();

    # Show message
    $self->{message} = "Replaced $total occurrence" . ($total == 1 ? '' : 's');
    $self->{message_time} = time();
}

# Synchronous replace for small numbers of matches
sub _replace_all_sync {
    my ($self) = @_;

    my $matches = $self->{find_matches};
    return unless @$matches;

    my $doc = $self->active_doc();
    my $replacement = $self->{find_replace_widget}->value();

    # Sort by line/col descending to preserve offsets
    my @sorted = sort {
        $b->{line} <=> $a->{line} ||
        $b->{col} <=> $a->{col}
    } @$matches;

    my $engine = $self->active_find_engine();
    for my $match (@sorted) {
        my $expanded = $engine->expand_replacement_for_match($match, $replacement);
        my $offset = $doc->line_col_to_offset($match->{line}, $match->{col});
        $doc->replace($offset, $offset + $match->{length}, $expanded);
    }

    # Update matches
    $self->_update_find_matches();

    my $count = scalar @sorted;
    $self->{message} = "Replaced $count occurrence" . ($count == 1 ? '' : 's');
    $self->{message_time} = time();
}

sub _apply_replace_preview {
    my ($self) = @_;

    my $view = $self->active_view();
    my $engine = $self->active_find_engine();
    my $replacement = $self->{find_replace_widget}->value();

    # Get viewport bounds
    my $viewport_start = $view->scroll_line();
    my $viewport_end = $viewport_start + $view->viewport_rows();

    # Use FindEngine's virtual preview (no buffer modification!)
    # This returns a hash of line_num => { text => "...", highlights => [...] }
    my $preview = $engine->preview_viewport($replacement, $viewport_start, $viewport_end);

    # Store preview data for Renderer
    $self->{find_replace_preview} = $preview;

    # Build find_replaced from viewport matches for current highlighting
    my $viewport_matches = $engine->viewport_matches();
    my @replaced;
    for my $match (@$viewport_matches) {
        push @replaced, {
            line   => $match->{line},
            col    => $match->{col},
            length => length($replacement),  # Replacement length, not original match length
        };
    }
    $self->{find_replaced} = \@replaced;
}

# =============================================================================
# File Picker Handling
# =============================================================================

# =============================================================================
# Editing Commands
# =============================================================================

sub do_insert_char {
    my ($self, $char) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    # Column selection: insert on each line
    if ($view->column_select() && $view->has_selection()) {
        $self->_column_insert_char($char);
        return;
    }

    # Delete selection first if any
    if ($view->has_selection()) {
        $self->delete_selection();
    }

    my $offset = $doc->line_col_to_offset(
        $view->cursor_line(),
        $view->cursor_col()
    );

    $doc->insert($offset, $char);
    $view->move_right();
}

sub do_backspace {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    if ($view->column_select() && $view->has_selection()) {
        $self->_column_backspace();
        return;
    }

    if ($view->has_selection()) {
        $self->delete_selection();
        return;
    }

    my $line = $view->cursor_line();
    my $col = $view->cursor_col();

    return if $line == 0 && $col == 0;

    $view->move_left();

    my $offset = $doc->line_col_to_offset(
        $view->cursor_line(),
        $view->cursor_col()
    );

    $doc->delete($offset, 1);
}

sub do_delete {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    if ($view->column_select() && $view->has_selection()) {
        $self->_column_delete();
        return;
    }

    if ($view->has_selection()) {
        $self->delete_selection();
        return;
    }

    my $offset = $doc->line_col_to_offset(
        $view->cursor_line(),
        $view->cursor_col()
    );

    return if $offset >= $doc->length();

    $doc->delete($offset, 1);
}

sub do_enter {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    # Delete selection first
    if ($view->has_selection()) {
        $self->delete_selection();
    }

    my $offset = $doc->line_col_to_offset(
        $view->cursor_line(),
        $view->cursor_col()
    );

    # Get indentation of current line for auto-indent
    my $indent = '';
    if ($self->{prefs}->auto_indent()) {
        my $line_content = $doc->get_line_content($view->cursor_line());
        if ($line_content =~ /^(\s+)/) {
            $indent = $1;
        }
    }

    $doc->insert($offset, "\n" . $indent);

    # Invalidate wrap map so move_down() sees the updated line count
    $view->invalidate_wrap_map();

    # Move cursor to start of new line (after auto-indent)
    my $new_line = $view->cursor_line() + 1;
    $view->set_cursor($new_line, length($indent));
}

sub do_indent {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    if ($view->has_selection()) {
        # Indent selected lines
        my ($sl, $sc, $el, $ec) = $view->selection();
        my $indent = $self->{prefs}->tab_string();
        my $indent_len = length($indent);

        for my $line ($sl..$el) {
            my $offset = $doc->line_start_offset($line);
            $doc->insert($offset, $indent);
        }

        # Preserve selection with adjusted columns
        $view->set_cursor($sl, $sc + $indent_len, 0);  # Move to start
        $view->set_cursor($el, $ec + $indent_len, 1);  # Extend selection to end
        return;
    }

    # Insert tab at cursor
    my $offset = $doc->line_col_to_offset(
        $view->cursor_line(),
        $view->cursor_col()
    );

    my $indent = $self->{prefs}->tab_string();
    $doc->insert($offset, $indent);
    $view->move_right() for (1..length($indent));
}

sub do_unindent {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();
    my $tab_width = $self->{prefs}->tab_width();

    my ($start_line, $end_line, $had_selection);
    my ($orig_sc, $orig_ec);

    if ($view->has_selection()) {
        my ($sl, $sc, $el, $ec) = $view->selection();
        $start_line = $sl;
        $end_line = $el;
        $orig_sc = $sc;
        $orig_ec = $ec;
        $had_selection = 1;
    }
    else {
        $start_line = $view->cursor_line();
        $end_line = $start_line;
        $had_selection = 0;
    }

    my $first_removed = 0;
    my $last_removed = 0;

    for my $line ($start_line..$end_line) {
        my $content = $doc->get_line_content($line);
        my $removed = 0;

        if ($content =~ /^\t/) {
            # Remove one tab
            my $offset = $doc->line_start_offset($line);
            $doc->delete($offset, 1);
            $removed = 1;  # Actual character count removed
        }
        elsif ($content =~ /^( {1,$tab_width})/) {
            # Remove up to tab_width spaces
            my $spaces = length($1);
            my $offset = $doc->line_start_offset($line);
            $doc->delete($offset, $spaces);
            $removed = $spaces;
        }

        $first_removed = $removed if $line == $start_line;
        $last_removed = $removed if $line == $end_line;
    }

    # Preserve selection with adjusted columns
    if ($had_selection) {
        my $new_sc = $orig_sc > $first_removed ? $orig_sc - $first_removed : 0;
        my $new_ec = $orig_ec > $last_removed ? $orig_ec - $last_removed : 0;
        $view->set_cursor($start_line, $new_sc, 0);
        $view->set_cursor($end_line, $new_ec, 1);
    }
    else {
        # Adjust cursor position for single-line unindent
        my $cur_col = $view->cursor_col();
        my $new_col = $cur_col > $first_removed ? $cur_col - $first_removed : 0;
        $view->set_cursor($start_line, $new_col, 0);
    }
}

# =============================================================================
# Move/Duplicate Lines
# =============================================================================

sub do_move_line_up {
    my ($self) = @_;
    $self->_move_lines(-1);
}

sub do_move_line_down {
    my ($self) = @_;
    $self->_move_lines(1);
}

sub _move_lines {
    my ($self, $direction) = @_;  # -1 = up, 1 = down

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    # Determine line range (expand selection to full lines)
    my ($start_line, $end_line, $orig_sc, $orig_ec);
    if ($view->has_selection()) {
        my ($sl, $sc, $el, $ec) = $view->selection();
        $start_line = $sl;
        $end_line = $el;
        $orig_sc = $sc;
        $orig_ec = $ec;
        # If selection ends at col 0, don't include that line
        # (common when selecting by moving cursor down past lines)
        if ($ec == 0 && $el > $sl) {
            $end_line = $el - 1;
            $orig_ec = $doc->line_length($end_line);
        }
    }
    else {
        $start_line = $view->cursor_line();
        $end_line = $start_line;
    }

    # Check boundaries
    if ($direction < 0 && $start_line == 0) {
        return;  # Can't move up from first line
    }
    if ($direction > 0 && $end_line >= $doc->line_count() - 1) {
        return;  # Can't move down from last line
    }

    # Get the text of lines to move (including newlines)
    my $move_start = $doc->line_start_offset($start_line);
    my $move_end = $end_line == $doc->line_count() - 1
        ? $doc->length()
        : $doc->line_start_offset($end_line + 1);
    my $move_text = $doc->get_text($move_start, $move_end);

    # Get the adjacent line we're swapping with
    my $swap_line = $direction < 0 ? $start_line - 1 : $end_line + 1;
    my $swap_start = $doc->line_start_offset($swap_line);
    my $swap_end = $swap_line == $doc->line_count() - 1
        ? $doc->length()
        : $doc->line_start_offset($swap_line + 1);
    my $swap_text = $doc->get_text($swap_start, $swap_end);

    # Handle edge case: last line has no trailing newline
    if ($direction > 0 && $swap_line == $doc->line_count() - 1) {
        # Moving down to swap with last line
        # swap_text (last line) needs newline since it's moving to middle
        # move_text loses its trailing newline since it's becoming last
        $swap_text .= "\n" unless $swap_text =~ /\n$/;
        $move_text =~ s/\n$//;
    }
    elsif ($direction < 0 && $end_line == $doc->line_count() - 1) {
        # Moving up when selection includes last line
        # move_text (includes last line) needs newline since it's moving to middle
        # swap_text loses its trailing newline since it's becoming last
        $move_text .= "\n" unless $move_text =~ /\n$/;
        $swap_text =~ s/\n$//;
    }

    # Perform the swap by deleting and reinserting
    my $full_start = $direction < 0 ? $swap_start : $move_start;
    my $full_end = $direction < 0 ? $move_end : $swap_end;

    # Delete the entire range
    $doc->delete($full_start, $full_end - $full_start);

    # Insert in new order
    if ($direction < 0) {
        # Moving up: insert moved text, then swap text
        $doc->insert($full_start, $move_text . $swap_text);
    }
    else {
        # Moving down: insert swap text, then moved text
        $doc->insert($full_start, $swap_text . $move_text);
    }

    # Update cursor/selection to follow moved lines
    my $new_start_line = $start_line + $direction;
    my $new_end_line = $end_line + $direction;

    if (defined $orig_sc) {
        # Had selection - restore it on the new line positions
        $view->clear_selection();
        $view->set_cursor($new_start_line, $orig_sc, 0);
        $view->set_cursor($new_end_line, $orig_ec, 1);
    }
    else {
        my $col = $view->cursor_col();
        $view->set_cursor($new_start_line, $col, 0);
    }
}

sub do_duplicate_line_up {
    my ($self) = @_;
    $self->_duplicate_lines(-1);
}

sub do_duplicate_line_down {
    my ($self) = @_;
    $self->_duplicate_lines(1);
}

# Column selection: extend (or start) rectangular selection vertically
sub do_column_select_up {
    my ($self) = @_;
    my $view = $self->active_view();
    return if $view->cursor_line() <= 0;

    $view->start_column_selection() unless $view->has_selection();
    # Move by document line (skip continuation lines when word wrap is active)
    my $new_line = $view->cursor_line() - 1;
    $view->set_cursor($new_line, $view->cursor_col(), 1);
    $view->ensure_cursor_visible();
}

sub do_column_select_down {
    my ($self) = @_;
    my $view = $self->active_view();
    my $doc = $self->active_doc();
    return if $view->cursor_line() >= $doc->line_count() - 1;

    $view->start_column_selection() unless $view->has_selection();
    # Move by document line (skip continuation lines when word wrap is active)
    my $new_line = $view->cursor_line() + 1;
    $view->set_cursor($new_line, $view->cursor_col(), 1);
    $view->ensure_cursor_visible();
}

sub do_column_select_left {
    my ($self) = @_;
    my $view = $self->active_view();
    return if $view->cursor_col() <= 0;

    $view->start_column_selection() unless $view->has_selection();
    $view->move_left(1);  # extend_selection = true
}

sub do_column_select_right {
    my ($self) = @_;
    my $view = $self->active_view();

    $view->start_column_selection() unless $view->has_selection();
    $view->move_right(1);  # extend_selection = true
}

sub _duplicate_lines {
    my ($self, $direction) = @_;  # -1 = up, 1 = down

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    # Determine line range (expand selection to full lines)
    my ($start_line, $end_line);
    if ($view->has_selection()) {
        my ($sl, $sc, $el, $ec) = $view->selection();
        $start_line = $sl;
        $end_line = $el;
        # If selection ends at col 0, don't include that line
        if ($ec == 0 && $el > $sl) {
            $end_line = $el - 1;
        }
    }
    else {
        $start_line = $view->cursor_line();
        $end_line = $start_line;
    }

    # Get the text of lines to duplicate
    my $dup_start = $doc->line_start_offset($start_line);
    my $dup_end = $end_line == $doc->line_count() - 1
        ? $doc->length()
        : $doc->line_start_offset($end_line + 1);
    my $dup_text = $doc->get_text($dup_start, $dup_end);

    # Ensure text ends with newline for proper insertion
    my $needs_newline = $dup_text !~ /\n$/;
    $dup_text .= "\n" if $needs_newline;

    # Insert the duplicate
    my $insert_pos;
    my $cursor_line_delta;

    if ($direction < 0) {
        # Duplicate above: insert at start of first line
        $insert_pos = $dup_start;
        $cursor_line_delta = 0;  # Cursor stays on original (which shifted down)
    }
    else {
        # Duplicate below: insert after last line
        $insert_pos = $dup_end;
        if ($needs_newline) {
            # Last line didn't have newline, we need to add one before
            $doc->insert($dup_end, "\n");
            $insert_pos = $dup_end + 1;
            $dup_text =~ s/\n$//;  # Remove the newline we added to dup_text
        }
        $cursor_line_delta = $end_line - $start_line + 1;  # Move to duplicate
    }

    $doc->insert($insert_pos, $dup_text);

    # Move cursor to the duplicate
    my $new_line = $start_line + $cursor_line_delta;
    my $col = $view->cursor_col();
    $view->clear_selection();
    $view->set_cursor($new_line, $col, 0);
}

sub delete_selection {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    return unless $view->has_selection();

    # Column selection: delete rectangle content
    if ($view->column_select()) {
        $self->_column_delete_selection();
        return;
    }

    my ($start, $end) = $view->selection_offsets();
    $doc->delete($start, $end - $start);

    my ($line, $col) = $doc->offset_to_line_col($start);
    $view->clear_selection();
    $view->set_cursor($line, $col);
}

# =============================================================================
# Column (rectangular) editing helpers
# =============================================================================

# Delete the content within the column selection rectangle
sub _column_delete_selection {
    my ($self) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();

    my ($top, $left, $bottom, $right) = $view->column_selection();
    return unless defined $top;

    $doc->begin_undo_group();

    for my $ln (reverse $top .. $bottom) {
        my $line_len = $doc->line_length($ln);
        next if $line_len <= $left;
        my $del_end = $right < $line_len ? $right : $line_len;
        my $del_len = $del_end - $left;
        next if $del_len <= 0;
        my $offset = $doc->line_col_to_offset($ln, $left);
        $doc->delete($offset, $del_len);
    }

    $doc->end_undo_group();

    # Collapse to zero-width column cursor at left edge
    $view->clear_selection();
    $view->{column_select} = 1;
    $view->{selection_anchor_line} = $top;
    $view->{selection_anchor_col} = $left;
    $view->{cursor_line} = $bottom;
    $view->{cursor_col} = $left;
    $view->{_preferred_col} = $left;
    $view->ensure_cursor_visible();
}

# Insert a character at each line in the column selection
sub _column_insert_char {
    my ($self, $char) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();

    my ($top, $left, $bottom, $right) = $view->column_selection();
    return unless defined $top;
    my $has_width = ($left != $right);

    $doc->begin_undo_group();

    for my $ln (reverse $top .. $bottom) {
        my $line_len = $doc->line_length($ln);

        # Pad line with spaces if shorter than left edge
        if ($line_len < $left) {
            my $pad = ' ' x ($left - $line_len);
            my $offset = $doc->line_col_to_offset($ln, $line_len);
            $doc->insert($offset, $pad);
        }

        if ($has_width) {
            # Delete the rectangle content first
            my $cur_len = $doc->line_length($ln);
            my $del_end = $right < $cur_len ? $right : $cur_len;
            my $del_len = $del_end - $left;
            if ($del_len > 0) {
                my $offset = $doc->line_col_to_offset($ln, $left);
                $doc->delete($offset, $del_len);
            }
        }

        # Insert the character
        my $offset = $doc->line_col_to_offset($ln, $left);
        $doc->insert($offset, $char);
    }

    $doc->end_undo_group();

    # Collapse to zero-width column cursor at left + char_length
    my $new_col = $left + CORE::length($char);
    $view->clear_selection();
    $view->{column_select} = 1;
    $view->{selection_anchor_line} = $top;
    $view->{selection_anchor_col} = $new_col;
    $view->{cursor_line} = $bottom;
    $view->{cursor_col} = $new_col;
    $view->{_preferred_col} = $new_col;
    $view->ensure_cursor_visible();
}

# Backspace in column selection mode
sub _column_backspace {
    my ($self) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();

    my ($top, $left, $bottom, $right) = $view->column_selection();
    return unless defined $top;
    my $has_width = ($left != $right);

    if ($has_width) {
        # Delete rectangle content
        $self->_column_delete_selection();
        return;
    }

    # Zero-width: delete one char before cursor column on each line
    return if $left == 0;

    $doc->begin_undo_group();

    for my $ln (reverse $top .. $bottom) {
        my $line_len = $doc->line_length($ln);
        next if $line_len < $left;  # Skip lines shorter than cursor
        my $offset = $doc->line_col_to_offset($ln, $left - 1);
        $doc->delete($offset, 1);
    }

    $doc->end_undo_group();

    # Move cursor column left by 1
    my $new_col = $left - 1;
    $view->{selection_anchor_col} = $new_col;
    $view->{cursor_col} = $new_col;
    $view->{_preferred_col} = $new_col;
    $view->ensure_cursor_visible();
}

# Delete key in column selection mode
sub _column_delete {
    my ($self) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();

    my ($top, $left, $bottom, $right) = $view->column_selection();
    return unless defined $top;
    my $has_width = ($left != $right);

    if ($has_width) {
        # Delete rectangle content
        $self->_column_delete_selection();
        return;
    }

    # Zero-width: delete one char at cursor column on each line
    $doc->begin_undo_group();

    for my $ln (reverse $top .. $bottom) {
        my $line_len = $doc->line_length($ln);
        next if $line_len <= $left;  # Skip lines at or shorter than cursor
        my $offset = $doc->line_col_to_offset($ln, $left);
        $doc->delete($offset, 1);
    }

    $doc->end_undo_group();
    $view->ensure_cursor_visible();
}

# =============================================================================
# LineMap for inline diff expansion
# =============================================================================

# Ensure a LineMap exists on the view (creates one from current document hunks)
sub _ensure_line_map {
    my ($self) = @_;
    my $view = $self->active_view();
    my $doc = $self->active_doc();
    return unless $view && $doc;

    my $lm = $view->line_map();
    if (!$lm) {
        $lm = Zepto::LineMap->new(
            doc_line_count => $doc->line_count(),
            hunks          => $doc->vcs_hunks(),
        );
        $view->set_line_map($lm);
    }
    return $lm;
}

# Sync LineMap with current document state (call after diff recomputation)
sub _sync_line_map {
    my ($self) = @_;
    my $view = $self->active_view();
    my $doc = $self->active_doc();
    return unless $view && $doc;

    my $lm = $view->line_map();
    return unless $lm;

    # Update hunks and doc line count — collapses all expanded hunks
    $lm->update(
        doc_line_count => $doc->line_count(),
        hunks          => $doc->vcs_hunks(),
    );
    $self->{_perf}{linemap_sync} = 1;
}

# Build sorted list of hunk anchor lines (first line of each hunk)
sub _hunk_anchors {
    my ($self) = @_;
    my $doc = $self->active_doc();
    my $hunks = $doc->vcs_hunks();
    return [] unless $hunks && @$hunks;

    my @anchors;
    for my $i (0 .. $#$hunks) {
        my $h = $hunks->[$i];
        my $anchor;
        if ($h->{type} eq 'deleted') {
            $anchor = $h->{prev_curr_line} == -1 ? 0 : $h->{prev_curr_line};
        } else {
            $anchor = $h->{current_lines}[0];
        }
        push @anchors, { line => $anchor, hunk_idx => $i };
    }
    return [ sort { $a->{line} <=> $b->{line} } @anchors ];
}

# Navigate to the next VCS hunk (wraps around)
sub cmd_next_change {
    my ($self) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();
    return unless $doc && $view;

    my $anchors = $self->_hunk_anchors();
    return $self->show_message("No changes") unless @$anchors;

    my $cursor = $view->cursor_line();
    my $current_hunk = $doc->vcs_hunk_at_line($cursor);

    # Find the next hunk after the current one
    for my $a (@$anchors) {
        next if defined $current_hunk && $a->{hunk_idx} == $current_hunk;
        if ($a->{line} > $cursor) {
            $self->_navigate_to_hunk($a);
            return;
        }
    }
    # Wrap to first hunk
    my $first = $anchors->[0];
    if (defined $current_hunk && $first->{hunk_idx} == $current_hunk && @$anchors > 1) {
        $first = $anchors->[1];
    }
    $self->_navigate_to_hunk($first);
}

# Navigate to the previous VCS hunk (wraps around)
sub cmd_prev_change {
    my ($self) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();
    return unless $doc && $view;

    my $anchors = $self->_hunk_anchors();
    return $self->show_message("No changes") unless @$anchors;

    my $cursor = $view->cursor_line();
    my $current_hunk = $doc->vcs_hunk_at_line($cursor);

    # Find the previous hunk before the current one
    for my $a (reverse @$anchors) {
        next if defined $current_hunk && $a->{hunk_idx} == $current_hunk;
        if ($a->{line} < $cursor) {
            $self->_navigate_to_hunk($a);
            return;
        }
    }
    # Wrap to last hunk
    my $last = $anchors->[-1];
    if (defined $current_hunk && $last->{hunk_idx} == $current_hunk && @$anchors > 1) {
        $last = $anchors->[-2];
    }
    $self->_navigate_to_hunk($last);
}

# Navigate to a hunk: expand it, position cursor, center viewport with old lines visible
sub _navigate_to_hunk {
    my ($self, $anchor) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();
    my $hunk_idx = $anchor->{hunk_idx};

    $self->_record_location();

    # Auto-expand the hunk
    $self->_ensure_line_map();
    my $lm = $view->line_map();
    if (!$lm->is_expanded($hunk_idx)) {
        $lm->toggle_hunk($hunk_idx);
    }

    # Move cursor to first line of the hunk
    $view->set_cursor($anchor->{line}, 0);

    # Center viewport, accounting for old lines above the anchor
    my $hunks = $doc->vcs_hunks();
    my $h = $hunks->[$hunk_idx];
    my $old_line_count = ($h->{type} eq 'modified' || $h->{type} eq 'deleted')
        ? scalar @{$h->{base_lines}} : 0;

    my $viewport = $view->viewport_rows();
    my $scroll = $view->scroll_line();

    # The visual block starts $old_line_count display rows before the anchor line.
    # Center the whole block (old + new lines) in the viewport.
    my $block_start = $anchor->{line} - $old_line_count;  # approximate doc line of visual top
    $block_start = 0 if $block_start < 0;

    # If already well-positioned, don't jump
    my $margin = int($viewport / 4);
    if ($block_start >= $scroll + $margin &&
        $anchor->{line} < $scroll + $viewport - $margin) {
        return;
    }

    # Center the block in viewport
    my $new_scroll = $block_start - int($viewport / 4);
    $new_scroll = 0 if $new_scroll < 0;
    my $max_scroll = $doc->line_count() - $viewport;
    $new_scroll = $max_scroll if $max_scroll > 0 && $new_scroll > $max_scroll;
    $view->{scroll_line} = $new_scroll;
}

# Toggle inline diff expansion at cursor position
sub cmd_toggle_diff {
    my ($self) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();
    return unless $doc && $view;

    my $hunk_idx = $doc->vcs_hunk_at_line($view->cursor_line());
    if (defined $hunk_idx) {
        $self->_ensure_line_map();
        my $lm = $view->line_map();
        $lm->toggle_hunk($hunk_idx);
    } else {
        $self->show_message("No change at cursor");
    }
}

# =============================================================================
# File Tree
# =============================================================================

sub handle_tree_event {
    my ($self, $event) = @_;
    my $tree = $self->{file_tree};

    if ($event->{type} eq 'key') {
        my $key = $event->{key};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');

        if    ($key eq 'up')       { $tree->move_up(); $self->_tree_preview_current(); }
        elsif ($key eq 'down')     { $tree->move_down(); $self->_tree_preview_current(); }
        elsif ($key eq 'left')     { $tree->collapse_current(); }
        elsif ($key eq 'right')    { $tree->expand_current(); }
        elsif ($key eq 'enter')    { $self->_tree_open_selected(); }
        elsif ($key eq 'escape') {
            if ($tree->filter_active()) {
                my $had_query = length($tree->filter_query() // '');
                $tree->clear_filter();
                # If filter had no query, also unfocus (single Esc exits)
                $self->_tree_unfocus() unless $had_query;
            }
            else { $self->_tree_unfocus(); }
        }
        elsif ($key eq 'pageup')   { $tree->page_up($tree->viewport_height()); }
        elsif ($key eq 'pagedown') { $tree->page_down($tree->viewport_height()); }
        elsif ($key eq 'home')     { $tree->home(); }
        elsif ($key eq 'end')      { $tree->end(); }
        elsif ($key eq 'backspace') { $tree->filter_backspace(); }
    }
    elsif ($event->{type} eq 'char') {
        my $char = $event->{char};
        if    ($char eq '{') { $tree->shrink(2); }
        elsif ($char eq '}') { $tree->grow(2); }
        elsif ($char eq ' ') {
            if ($tree->filter_active()) { $tree->filter_append_char($char); }
            else { $tree->toggle_current(); }
        }
        elsif ($char eq '/') {
            if (!$tree->filter_active()) { $tree->start_filter(); }
            else { $tree->filter_append_char($char); }
        }
        else {
            # Auto-start filter on any other character
            if (!$tree->filter_active()) { $tree->start_filter(); }
            $tree->filter_append_char($char);
        }
    }
    elsif ($event->{type} eq 'mouse') {
        $self->handle_mouse_event($event);
    }
}

sub cmd_toggle_tree {
    my ($self) = @_;

    if ($self->{file_tree}) {
        if ($self->{file_tree}->focused()) {
            $self->_tree_unfocus();
        } else {
            $self->{file_tree}->refresh();
            $self->{file_tree}->set_focused(1);
            $self->_tree_reveal_current();
        }
    } else {
        # Create tree if it doesn't exist
        $self->{file_tree} = Zepto::FileTree->new(root_path => '.');
        $self->{file_tree}->set_focused(1);
        $self->_tree_reveal_current();
    }
}

sub _tree_reveal_current {
    my ($self) = @_;
    my $tree = $self->{file_tree};
    return unless $tree;

    if ($self->active_file_path()) {
        $tree->set_current_file($self->active_file_path());
        $tree->expand_to_path($self->active_file_path());
    }
}

use constant PREVIEW_MAX_FILE_SIZE => 100_000;  # 100KB — skip preview for large files

sub _tree_preview_current {
    my ($self) = @_;
    my $tree = $self->{file_tree};
    my $node = $tree->cursor_node();

    # Cancel preview when cursor is on a directory or no node
    if (!$node || $node->{is_dir}) {
        if ($tree->{preview_active}) {
            $self->_close_preview_tab();
            if (defined $tree->{pre_preview_tab_index}) {
                my $idx = $tree->{pre_preview_tab_index};
                $idx = 0 if $idx >= $self->{tab_manager}->tab_count();
                $self->_switch_to_tab($idx);
            }
            $tree->{preview_active} = 0;
            $tree->{preview_path} = undef;
        }
        return;
    }

    my $path = $node->{path};
    return if $tree->{preview_path} && $tree->{preview_path} eq $path;

    # Skip preview for large files to avoid UI freeze
    # Use absolute path for stat since tree paths may be relative
    my $abs_path = File::Spec->rel2abs($path, $tree->root_path());
    my $file_size = -s $abs_path;
    if (defined $file_size && $file_size > PREVIEW_MAX_FILE_SIZE) {
        # Cancel any active preview and show nothing
        if ($tree->{preview_active}) {
            $self->_close_preview_tab();
            if (defined $tree->{pre_preview_tab_index}) {
                my $idx = $tree->{pre_preview_tab_index};
                $idx = 0 if $idx >= $self->{tab_manager}->tab_count();
                $self->_switch_to_tab($idx);
            }
            $tree->{preview_active} = 0;
            $tree->{preview_path} = undef;
        }
        return;
    }

    # If already previewing a different file, close that preview tab first
    if ($tree->{preview_active}) {
        $self->_close_preview_tab();
    } else {
        # Remember which tab to return to
        $tree->{pre_preview_tab_index} = $self->{tab_manager}->active_index();
    }

    # Check if file already open in a tab — just switch to it
    my $existing = $self->{tab_manager}->find_tab_by_path($path);
    if (defined $existing) {
        $self->_switch_to_tab($existing);
        $tree->{preview_active} = 1;
        $tree->{preview_path} = $path;
        $tree->{_preview_is_existing_tab} = 1;
        return;
    }

    # Open file in a new transient tab (skip VCS to keep preview instant)
    eval {
        my ($doc, $view, $fe, $hl) = $self->_create_document_state($path, skip_vcs => 1);
        $self->{tab_manager}->add_tab(
            document => $doc, view => $view,
            find_engine => $fe, highlighter => $hl,
            file_path => $path,
        );
        $tree->{preview_active} = 1;
        $tree->{preview_path} = $path;
        $tree->{_preview_is_existing_tab} = 0;
    };
}

sub _close_preview_tab {
    my ($self) = @_;
    my $tree = $self->{file_tree};

    # Only close if it's a transient tab we created
    return unless $tree->{preview_active} && !$tree->{_preview_is_existing_tab};

    my $preview_path = $tree->{preview_path};
    return unless defined $preview_path;

    # Find and remove the preview tab
    my $idx = $self->{tab_manager}->find_tab_by_path($preview_path);
    if (defined $idx) {
        $self->{tab_manager}->remove_tab($idx);
    }
}

sub _tree_unfocus {
    my ($self) = @_;
    my $tree = $self->{file_tree};

    # Cancel preview: close transient tab, return to original
    if ($tree->{preview_active} && !$tree->{_preview_is_existing_tab}) {
        $self->_close_preview_tab();
    }
    # Restore original tab
    if (defined $tree->{pre_preview_tab_index}) {
        my $idx = $tree->{pre_preview_tab_index};
        $idx = 0 if $idx >= $self->{tab_manager}->tab_count();
        $self->_switch_to_tab($idx);
    }
    $tree->{preview_active} = 0;
    $tree->{preview_path} = undef;
    $tree->{pre_preview_tab_index} = undef;
    $tree->set_focused(0);

    # Now that tree is unfocused, update highlight to match active tab
    if ($self->active_file_path()) {
        $tree->set_current_file($self->active_file_path());
        $tree->expand_to_path($self->active_file_path());
    }
}

# Check if a tab at the given index is an empty, unedited, untitled tab.
# Returns the index if it should be closed, undef otherwise.
sub _empty_untitled_tab_index {
    my ($self, $idx) = @_;
    return undef unless defined $idx;
    my $tab = $self->{tab_manager}->tab_at($idx);
    return undef unless $tab;
    return undef if $tab->{file_path};      # has a real file
    my $doc = $tab->{document};
    return undef unless $doc;
    return undef if $doc->is_dirty();       # has been edited
    # Check if content is empty (new doc has 1 empty line)
    return undef if $doc->line_count() > 1;
    if ($doc->line_count() == 1) {
        return undef if $doc->get_line_content(0) ne '';
    }
    return $idx;
}

sub _tree_open_selected {
    my ($self) = @_;
    my $tree = $self->{file_tree};
    my $node = $tree->cursor_node();
    return unless $node;

    if ($node->{is_dir}) {
        $tree->toggle_current();
        return;
    }

    # If previewing this file, confirm it (keep the tab, init VCS now)
    if ($tree->{preview_active}) {
        # Preview was loaded without VCS — initialize it now for gutter indicators
        $self->active_doc()->init_vcs();
        # Check if the pre-preview tab was an empty untitled tab to close
        my $close_idx = $self->_empty_untitled_tab_index($tree->{pre_preview_tab_index});
        $tree->{preview_active} = 0;
        $tree->{preview_path} = undef;
        $tree->{pre_preview_tab_index} = undef;
        # Close the empty untitled tab after clearing preview state
        if (defined $close_idx) {
            $self->{tab_manager}->remove_tab($close_idx);
        }
    } else {
        # Open file via existing _load_file (handles duplicate detection)
        $self->_load_file($node->{path});
    }

    # Clear filter if active (return tree to browse mode)
    if ($tree->filter_active()) {
        $tree->clear_filter();
    }

    $tree->set_current_file($node->{path});
    $tree->expand_to_path($node->{path});
    $tree->set_focused(0);
}

# Map a scrollbar drag y-position to a scroll offset in the tree
sub _handle_tree_scrollbar_drag {
    my ($self, $row_in_content, $sb) = @_;
    my $tree = $self->{file_tree};
    return unless $sb->{visible} > 0 && $sb->{total} > $sb->{visible};

    # Clamp row to content area
    $row_in_content = 0 if $row_in_content < 0;
    $row_in_content = $sb->{visible} - 1 if $row_in_content >= $sb->{visible};

    # Map row position to scroll offset proportionally
    my $scroll_range = $sb->{total} - $sb->{visible};
    my $new_scroll = int(($row_in_content * $scroll_range) / ($sb->{visible} - 1 || 1));
    $new_scroll = 0 if $new_scroll < 0;
    $new_scroll = $scroll_range if $new_scroll > $scroll_range;

    $tree->set_scroll($new_scroll);
}

# =============================================================================
# Rendering
# =============================================================================

sub render {
    my ($self) = @_;

    # Keep terminal title in sync — cached, so no-op when unchanged
    $self->update_title();

    # Update VCS diff if needed (debounced)
    $self->active_doc()->update_vcs_diff($self->{_perf});

    # Check for external file changes (only in editing state, not during prompts)
    if ($self->{state} eq STATE_EDITING) {
        $self->_check_external_file_changes();
    }

    # If we have a LineMap, keep it in sync with current hunks/doc count
    if ($self->active_view()->line_map()) {
        my $lm = $self->active_view()->line_map();
        my $current_hunks = $self->active_doc()->vcs_hunks();
        my $current_count = $self->active_doc()->line_count();
        # Sync if hunks array ref changed (diff recomputed) or doc lines changed
        if ($current_hunks ne $lm->{hunks} || $current_count != $lm->{doc_line_count}) {
            $self->_sync_line_map();
        }
    }

    my $term = $self->{terminal};
    my ($rows, $cols) = $term->get_size();

    # Sync file tree viewport height and VCS statuses
    if ($self->{file_tree} && $self->{prefs}->show_tree()) {
        # Tree spans rows 2..N-1 (2 more rows than text area which starts at row 4)
        $self->{file_tree}->set_viewport_height($rows - RESERVED_ROWS + 2);
        # Update VCS statuses (debounced internally)
        # Use tree's own VCS provider (not tied to active doc which may be a preview tab)
        if (!$self->{_tree_vcs_provider}) {
            $self->{_tree_vcs_provider} = Zepto::VCS::Provider->detect(
                $self->{file_tree}->root_path()
            );
        }
        $self->{file_tree}->update_vcs_statuses($self->{_tree_vcs_provider})
            if $self->{_tree_vcs_provider};
    }

    # Update view size - account for gutter width
    my $line_count = $self->active_doc()->line_count();
    my $gutter_width = Zepto::Renderer->get_gutter_width($line_count);
    my $text_width = $cols - $gutter_width;
    $text_width = Zepto::Renderer::MIN_TEXT_WIDTH if $text_width < Zepto::Renderer::MIN_TEXT_WIDTH;

    $self->active_view()->set_viewport_size($rows - RESERVED_ROWS, $text_width);

    # Build/rebuild WrapMap for word wrap mode
    my $word_wrap_active = $self->_effective_word_wrap();
    if ($word_wrap_active) {
        {
            # Compute actual text content width (tree has priority over minimap)
            my $tree_width = 0;
            if ($self->{file_tree} && $self->{prefs}->show_tree() && $self->{file_tree}->panel_width() > 0) {
                my $tw = $self->{file_tree}->panel_width() + 1;
                my $remaining = $cols - $tw - $gutter_width;
                $tree_width = $tw if $remaining >= Zepto::Renderer::MIN_TEXT_WIDTH;
            }
            my $minimap_width = 0;
            if ($self->{prefs}->show_minimap() && $self->active_doc()->line_count() > ($rows - RESERVED_ROWS)) {
                my $tentative = $cols - $tree_width - $gutter_width - Zepto::Renderer::MINIMAP_WIDTH;
                $minimap_width = Zepto::Renderer::MINIMAP_WIDTH if $tentative >= Zepto::Renderer::MIN_TEXT_WIDTH;
            }
            my $wrap_width = $cols - $tree_width - $gutter_width - $minimap_width;
            $wrap_width = Zepto::Renderer::MIN_TEXT_WIDTH if $wrap_width < Zepto::Renderer::MIN_TEXT_WIDTH;

            my $wm = $self->active_view()->wrap_map();
            if (!$wm || $wm->{width} != $wrap_width) {
                $wm = Zepto::WrapMap->new(
                    document  => $self->active_doc(),
                    width     => $wrap_width,
                    tab_width => $self->{prefs}->tab_width(),
                );
                $self->active_view()->set_wrap_map($wm);
                $self->{_perf}{wrapmap_rebuild} = 1;
            }
            # WrapMap is invalidated by View::invalidate_wrap_map() when
            # content actually changes (insert, delete, undo, redo, reload).
            # No need to invalidate unconditionally on every render.
        }
    } else {
        $self->active_view()->set_wrap_map(undef) if $self->active_view()->wrap_map();
    }

    $self->active_view()->ensure_cursor_visible();

    my $output = Zepto::Renderer->render(
        document    => $self->active_doc(),
        view        => $self->active_view(),
        theme       => $self->{theme},
        prefs       => $self->{prefs},
        rows        => $rows,
        cols        => $cols,
        message     => $self->{message},
        highlighter => $self->active_highlighter(),
        word_wrap_active => $word_wrap_active,
        ui          => {
            editor => $self,
            dialog => $self->{dialog},
            palette => ($self->{state} eq STATE_PALETTE && $self->{palette_widget}) ? {
                query          => $self->{palette_widget}->value(),
                query_cursor   => $self->{palette_widget}->cursor(),
                palette_widget => $self->{palette_widget},
                cursor         => $self->{palette_cursor},
                scroll         => $self->{palette_scroll},
                filtered       => $self->{palette_filtered},
                editor         => $self,
                mode           => $self->{palette_mode} // 'commands',
            } : undef,
            prompt => $self->{prompt},
            footer_input => $self->{footer_input},
            tabs => $self->{tab_manager}->tabs_for_render(),
            active_tab_index => $self->{tab_manager}->active_index(),
            tab_manager => $self->{tab_manager},
            file_tree => ($self->{prefs}->show_tree() && $self->{file_tree}) ? $self->{file_tree} : undef,
            find_mode => ($self->{state} eq STATE_FIND) ? {
                value          => $self->{find_widget}->value(),
                cursor         => $self->{find_widget}->cursor(),
                find_widget    => $self->{find_widget},
                matches        => $self->{find_matches},
                replaced       => $self->{find_replaced},
                replace_preview => $self->{find_replace_preview},  # Virtual preview data
                current        => $self->{find_current},
                regex          => $self->{find_regex},
                case           => $self->{find_case},
                replace_value  => $self->{find_replace_widget}->value(),
                replace_cursor => $self->{find_replace_widget}->cursor(),
                replace_widget => $self->{find_replace_widget},
                replace_active => $self->{find_replace_active},
                replace_all    => $self->{find_replace_all},
                focus          => $self->{find_focus},
                match_count    => $self->active_find_engine() ? $self->active_find_engine()->match_count() : 0,
                capture_count  => ($self->{find_regex} && $self->active_find_engine())
                    ? $self->active_find_engine()->capture_group_count() : 0,
                capture_regex  => ($self->{find_regex} && $self->active_find_engine())
                    ? $self->active_find_engine()->capture_regex() : undef,
                is_searching   => $self->active_find_engine() ? $self->active_find_engine()->is_searching() : 0,
                is_replacing   => $self->{_replace_active} // 0,
                replace_progress => $self->{_replace_progress} // 0,
                replace_total  => $self->{_replace_total} // 0,
            } : undef,
        },
    );

    $term->write($output);
}

sub show_message {
    my ($self, $msg) = @_;
    $self->{message} = $msg;
}

# =============================================================================
# External file change detection
# =============================================================================

sub _check_external_file_changes {
    my ($self) = @_;
    my $doc = $self->active_doc();
    return unless $doc && defined $doc->path();

    # Debounce — stat() on every render is wasteful
    my $now = time();
    $self->{_last_external_check} //= 0;
    return if ($now - $self->{_last_external_check}) < EXTERNAL_CHECK_INTERVAL_SEC;
    $self->{_last_external_check} = $now;
    $self->{_perf}{file_stat} = 1;

    return unless $doc->check_external_changes();

    if ($doc->is_dirty()) {
        # Buffer has local modifications — ask the user
        my $name = $doc->filename() // $doc->path();
        my $redo_icon = Zepto::Chars->get('redo');
        $self->open_prompt(
            text => "File '$name' changed on disk.",
            options => [
                { key => 'r', label => 'Reload', icon => $redo_icon },
                { key => 'k', label => 'Keep local' },
            ],
            on_select => sub {
                my ($choice) = @_;
                if ($choice eq 'r') {
                    my $view = $self->active_view();
                    my $old_line = $view->cursor_line();
                    my $old_col = $view->cursor_col();
                    eval { $doc->reload_from_disk(); };
                    if ($@) {
                        $self->show_message("Reload error: $@");
                        return;
                    }
                    # Restore cursor (clamped to valid range)
                    my $max_line = $doc->line_count() - 1;
                    $max_line = 0 if $max_line < 0;
                    my $new_line = $old_line > $max_line ? $max_line : $old_line;
                    my $max_col = $doc->line_length($new_line);
                    my $new_col = $old_col > $max_col ? $max_col : $old_col;
                    $view->set_cursor($new_line, $new_col);
                    $view->invalidate_wrap_map();
                    $self->show_message("Reloaded: $name");
                }
                elsif ($choice eq 'k') {
                    # User chose to keep local — update mtime so we don't re-prompt
                    $doc->_capture_file_mtime();
                    $self->show_message("Keeping local changes");
                }
            },
        );
    }
    else {
        # No local modifications — silently reload
        my $view = $self->active_view();
        my $old_line = $view->cursor_line();
        my $old_col = $view->cursor_col();
        eval { $doc->reload_from_disk(); };
        if ($@) {
            $self->show_message("Reload error: $@");
            return;
        }
        # Restore cursor (clamped to valid range)
        my $max_line = $doc->line_count() - 1;
        $max_line = 0 if $max_line < 0;
        my $new_line = $old_line > $max_line ? $max_line : $old_line;
        my $max_col = $doc->line_length($new_line);
        my $new_col = $old_col > $max_col ? $max_col : $old_col;
        $view->set_cursor($new_line, $new_col);
        $view->invalidate_wrap_map();
    }
}

# =============================================================================
# Helpers
# =============================================================================

# Open a new untitled tab with the given text content
sub _open_content_tab {
    my ($self, $content, $name) = @_;
    my $doc = Zepto::Document->new(text => $content);
    my $highlighter = Zepto::Highlighter->new();
    my ($rows, $cols) = $self->{terminal}->get_size();
    my $gutter_width = Zepto::Renderer->get_gutter_width($doc->line_count());
    my $text_width = $cols - $gutter_width;
    $text_width = Zepto::Renderer::MIN_TEXT_WIDTH if $text_width < Zepto::Renderer::MIN_TEXT_WIDTH;

    my $view = Zepto::View->new(
        document      => $doc,
        viewport_rows => $rows - RESERVED_ROWS,
        viewport_cols => $text_width,
    );
    my $find_engine = Zepto::FindEngine->new(document => $doc);

    $self->{tab_manager}->add_tab(
        document      => $doc,
        view          => $view,
        find_engine   => $find_engine,
        highlighter   => $highlighter,
        file_path     => undef,
        untitled_name => $name,
    );
}

# =============================================================================
# Performance Profiling
# =============================================================================

use constant PERF_LOG_MAX_ENTRIES => 20;

sub _record_frame {
    my ($self, $timestamp, $total_ms, $event_ms, $render_ms, $input) = @_;

    # Classify event type from raw input
    my $event_type = 'timeout';
    if (defined $input && length $input) {
        my $ord = ord(substr($input, 0, 1));
        if ($ord == 27) {
            $event_type = length($input) > 1 ? 'alt' : 'escape';
        } elsif ($ord < 32) {
            $event_type = 'ctrl';
        } elsif ($input =~ /^\x1b\[M/ || $input =~ /^\x1b\[</) {
            $event_type = 'mouse';
        } else {
            $event_type = 'char';
        }
    }

    # Gather context
    my $file = '';
    my $lines = 0;
    if (my $doc = $self->active_doc()) {
        $file = $doc->filename() // '';
        $lines = $doc->line_count();
    }

    # Active features
    my @features;
    push @features, 'wrap' if $self->_effective_word_wrap();
    push @features, 'tree' if $self->{file_tree} && $self->{prefs}->show_tree();
    push @features, 'minimap' if $self->{prefs}->show_minimap();
    my $features_str = join(',', @features) || 'none';

    # Subsystem flags
    my @subs = sort keys %{$self->{_perf}};
    my $subsystems_str = join(',', @subs) || 'none';

    my $entry = {
        timestamp  => $timestamp,
        total_ms   => $total_ms,
        event_ms   => $event_ms,
        render_ms  => $render_ms,
        state      => uc($self->{state}),
        event_type => $event_type,
        file       => $file,
        lines      => $lines,
        features   => $features_str,
        subsystems => $subsystems_str,
    };

    my $log = $self->{_perf_log};
    if (@$log < PERF_LOG_MAX_ENTRIES) {
        push @$log, $entry;
        @$log = sort { $b->{total_ms} <=> $a->{total_ms} } @$log;
    } elsif ($total_ms > $log->[-1]{total_ms}) {
        $log->[-1] = $entry;
        @$log = sort { $b->{total_ms} <=> $a->{total_ms} } @$log;
    }
}

1;
