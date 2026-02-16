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

use Exporter 'import';
our @EXPORT_OK = qw(STATE_EDITING STATE_MENU STATE_DIALOG STATE_PROMPT STATE_FOOTER_INPUT STATE_FILE_PICKER STATE_FIND STATE_QUIT);

# Version for crash reports
our $VERSION = '0.1.0';

use Zepto::Document;
use Zepto::View;
use Zepto::Terminal;
use Zepto::Renderer;
use Zepto::InputParser;
use Zepto::Preferences;
use Zepto::Theme;
use Zepto::FilePicker;
use Zepto::Highlighter;
use Zepto::FindEngine;

# Editor states
use constant {
    STATE_EDITING      => 'editing',
    STATE_MENU         => 'menu',
    STATE_DIALOG       => 'dialog',
    STATE_PROMPT       => 'prompt',        # Simple choice in status bar
    STATE_FOOTER_INPUT => 'footer_input',  # Text input in status bar
    STATE_FILE_PICKER  => 'file_picker',   # Fuzzy file finder
    STATE_FIND         => 'find',          # Incremental find in status bar
    STATE_QUIT         => 'quit',
};

# Load command and menu modules (they add methods to this package)
use Zepto::Editor::Commands;
use Zepto::Editor::Menu;

# Timing and UI settings
use constant {
    INPUT_TIMEOUT_SEC   => 0.5,   # Seconds to wait for input
    MESSAGE_DISPLAY_SEC => 3,     # Seconds to show status messages
    RESERVED_ROWS       => 3,     # Rows for menu bar + ruler bar + status bar
};

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
        # Core components
        document    => undef,
        view        => undef,
        terminal    => $opts{terminal} // Zepto::Terminal->new(),
        parser      => Zepto::InputParser->new(),
        prefs       => $opts{prefs} // Zepto::Preferences->new(),
        theme       => undef,
        highlighter => Zepto::Highlighter->new(),

        # UI state
        state        => STATE_EDITING,
        menu_open    => undef,
        menu_selected => 0,
        dialog       => undef,
        message      => '',
        message_time => 0,

        # Search state
        search_term   => '',
        search_replace => '',
        last_search_pos => 0,

        # Incremental find state
        find_engine       => undef,   # FindEngine for async search
        find_input        => '',      # Current search input
        find_input_cursor => 0,       # Cursor position in input
        find_current      => 0,       # Index of current match (0-based)
        find_regex        => 0,       # Regex mode enabled
        find_case         => 0,       # Case-sensitive enabled

        # Replace state (extension of find)
        find_replace_input  => '',      # Replacement text
        find_replace_cursor => 0,       # Cursor position in replace input
        find_replace_active => 0,       # Is replace field visible?
        find_focus          => 'find',  # Which field has focus: 'find' or 'replace'
        find_replace_all    => 1,       # Replace all mode (vs replace one)

        # Clipboard
        clipboard    => '',

        # Quit confirmation
        quit_pending => 0,

        # Mouse button state for reliable drag detection
        mouse_button_down => 0,

        # File path from command line
        file_path    => $opts{file},

        # Prompt state (for status bar prompts)
        prompt       => undef,

        # Footer input state (for text input in status bar)
        footer_input => undef,

        # File picker state
        file_picker  => undef,
    }, $class;

    # Initialize theme
    $self->{theme} = Zepto::Theme->get_theme($self->{prefs}->theme());

    return $self;
}

# =============================================================================
# Initialization
# =============================================================================

sub init {
    my ($self) = @_;

    my $term = $self->{terminal};

    # Set process name (shows in ps/top)
    $0 = 'zepto';

    # Set cursor color and shape BEFORE raw mode (raw mode may interfere)
    my $cursor_color = $self->{theme}->color('cursor_color');
    if ($cursor_color) {
        print STDOUT "\x1b]12;${cursor_color}\x1b\\";  # OSC 12 - cursor color
    }
    print STDOUT "\x1b[5 q";  # DECSCUSR 5 - blinking bar cursor
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

    # Load or create document
    if ($self->{file_path} && -f $self->{file_path}) {
        $self->{document} = Zepto::Document->load($self->{file_path});
        $self->show_message("Loaded: " . $self->{file_path});
    }
    else {
        $self->{document} = Zepto::Document->new(
            path => $self->{file_path},
        );
        if ($self->{file_path}) {
            $self->show_message("New file: " . $self->{file_path});
        }
    }

    # Initialize syntax highlighting for the file
    $self->{highlighter}->set_file($self->{file_path});

    # If no grammar detected from extension, try shebang detection
    if (!$self->{highlighter}->has_grammar && $self->{document}->line_count() > 0) {
        my $first_line = $self->{document}->get_line_content(0);
        $self->{highlighter}->detect_from_shebang($first_line);
    }

    # Set terminal title
    $self->update_title();

    # Create view - account for gutter width in text area
    my ($rows, $cols) = $term->get_size();
    my $line_count = $self->{document}->line_count();
    my $gutter_width = Zepto::Renderer->get_gutter_width($line_count);
    my $text_width = $cols - $gutter_width;
    $text_width = Zepto::Renderer::MIN_TEXT_WIDTH if $text_width < Zepto::Renderer::MIN_TEXT_WIDTH;

    $self->{view} = Zepto::View->new(
        document => $self->{document},
        viewport_rows => $rows - RESERVED_ROWS,
        viewport_cols => $text_width,
    );

    # Create find engine for async search
    $self->{find_engine} = Zepto::FindEngine->new(
        document => $self->{document},
    );

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
            my $searching = $self->{find_engine} && $self->{find_engine}->is_searching;
            my $timeout = $searching ? 0.01 : INPUT_TIMEOUT_SEC;  # 10ms vs 500ms

            # Read input with timeout
            my $input = $self->{terminal}->read_blocking($timeout);

            my $needs_render = 0;

            # Clear message after timeout
            if ($self->{message} && time() - $self->{message_time} > MESSAGE_DISPLAY_SEC) {
                $self->{message} = '';
                $needs_render = 1;
            }

            if (length $input) {
                $self->handle_input($input);
                $needs_render = 1;
                $last_search_render = 0;  # Reset throttle on user input
            }

            # Continue background search if active
            if ($searching) {
                my $term = $self->{terminal};
                my $engine = $self->{find_engine};

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
            $self->render() if $needs_render;
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
    my $file = $self->{file_path} // '[no file]';
    my $state = $self->{state} // 'unknown';
    my $cursor_info = '';
    if ($self->{view}) {
        my $line = $self->{view}->cursor_line() + 1;
        my $col = $self->{view}->cursor_col() + 1;
        $cursor_info = "Cursor: line $line, col $col";
    }
    my $doc_info = '';
    if ($self->{document}) {
        my $lines = $self->{document}->line_count();
        my $dirty = $self->{document}->is_dirty() ? ' (modified)' : '';
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
    if ($self->{document} && $self->{document}->path()) {
        $title .= ' - ' . $self->{document}->filename();
    }
    elsif ($self->{file_path}) {
        my ($name) = $self->{file_path} =~ m{([^/]+)$};
        $title .= ' - ' . $name if $name;
    }

    $self->{terminal}->set_title($title);
}

# =============================================================================
# Input Handling
# =============================================================================

sub handle_input {
    my ($self, $input) = @_;

    my @events = $self->{parser}->parse($input);

    # Check for pending escape (e.g., standalone ESC key)
    if (!@events) {
        my $pending = $self->{parser}->flush_pending();
        push @events, $pending if $pending;
    }

    for my $event (@events) {
        $self->handle_event($event);
    }
}

sub handle_event {
    my ($self, $event) = @_;

    return unless $event;

    # Route to appropriate handler based on state
    if ($self->{state} eq STATE_DIALOG) {
        $self->handle_dialog_event($event);
    }
    elsif ($self->{state} eq STATE_MENU) {
        $self->handle_menu_event($event);
    }
    elsif ($self->{state} eq STATE_PROMPT) {
        $self->handle_prompt_event($event);
    }
    elsif ($self->{state} eq STATE_FOOTER_INPUT) {
        $self->handle_footer_input_event($event);
    }
    elsif ($self->{state} eq STATE_FILE_PICKER) {
        $self->handle_file_picker_event($event);
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

    my $type = $event->{type};
    my $view = $self->{view};
    my $doc = $self->{document};

    if ($type eq 'key') {
        my $key = $event->{key};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');
        my $shift = Zepto::InputParser::has_modifier($event, 'shift');
        my $alt = Zepto::InputParser::has_modifier($event, 'alt');

        # Navigation / Line movement
        if ($key eq 'up') {
            if ($alt && $shift) { $self->do_duplicate_line_up(); }
            elsif ($alt) { $self->do_move_line_up(); }
            else { $view->move_up($shift); }
        }
        elsif ($key eq 'down') {
            if ($alt && $shift) { $self->do_duplicate_line_down(); }
            elsif ($alt) { $self->do_move_line_down(); }
            else { $view->move_down($shift); }
        }
        elsif ($key eq 'left')  {
            if ($alt) { $view->move_word_left($shift); }
            else { $view->move_left($shift); }
        }
        elsif ($key eq 'right') {
            if ($alt) { $view->move_word_right($shift); }
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
        elsif ($key eq 'pageup')   { $view->move_page_up($shift); }
        elsif ($key eq 'pagedown') { $view->move_page_down($shift); }

        # Editing keys
        elsif ($key eq 'backspace') { $self->do_backspace(); }
        elsif ($key eq 'delete')    { $self->do_delete(); }
        elsif ($key eq 'enter')     { $self->do_enter(); }
        elsif ($key eq 'tab')       {
            if ($shift) { $self->do_unindent(); }
            else { $self->do_indent(); }
        }

        # Escape - close menu, clear selection, or open menu bar
        elsif ($key eq 'escape') {
            if ($self->{menu_open}) {
                $self->close_menu();
            }
            elsif ($view->has_selection()) {
                $view->clear_selection();
            }
            else {
                # Nothing to cancel - open menu bar
                $self->open_menu('f');
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
    elsif ($char eq 'w') { $self->cmd_save_and_quit(); }
    elsif ($char eq 'q') { $self->cmd_quit(); }

    # Edit operations
    elsif ($char eq 'z') { $self->cmd_undo(); }
    elsif ($char eq 'y') { $self->cmd_redo(); }
    elsif ($char eq 'x') { $self->cmd_cut(); }
    elsif ($char eq 'c') { $self->cmd_copy(); }
    elsif ($char eq 'v') { $self->cmd_paste(); }
    elsif ($char eq 'a') { $self->cmd_select_all(); }

    # Search operations
    elsif ($char eq 'f') { $self->cmd_find(); }
    elsif ($char eq 'j') { $self->cmd_find_next(); }
    elsif ($char eq 'k') { $self->cmd_find_prev(); }
    elsif ($char eq 'g') { $self->cmd_goto_line(); }

    # View
    elsif ($char eq 't') { $self->cmd_toggle_theme(); }
    elsif ($char eq 'p') { $self->cmd_toggle_powerline(); }

    # Reset quit pending for any other command
    $self->{quit_pending} = 0 unless $char eq 'q';
}

sub handle_alt_char {
    my ($self, $char) = @_;

    my $view = $self->{view};

    # Word movement (Option+Arrow on macOS sends ESC b/f)
    if    ($char eq 'b') { $view->move_word_left(); }
    elsif ($char eq 'f') { $view->move_word_right(); }
    # Menus accessed via Escape key, not Alt+letter
}

sub handle_mouse_event {
    my ($self, $event) = @_;

    my $action = $event->{action};
    my $x = $event->{x};
    my $y = $event->{y};
    my $shift = Zepto::InputParser::has_modifier($event, 'shift');

    my $term = $self->{terminal};
    my $view = $self->{view};

    if ($action eq 'press') {
        # Track mouse button state
        $self->{mouse_button_down} = 1;

        # Check if click is in menu bar (row 1)
        if ($y == 1) {
            $self->handle_menu_click($x);
            return;
        }

        # Ignore clicks on ruler bar (row 2)
        return if $y == 2;

        # Check if click is on status bar (last row) in find mode
        my ($rows, $cols) = $term->get_size();
        if ($y == $rows && $self->{state} eq STATE_FIND) {
            $self->handle_find_bar_click($x);
            return;
        }

        # Click in text area
        my $text_row = $y - 3;  # Adjust for menu bar (row 1) and ruler bar (row 2)
        my $line_count = $self->{document} ? $self->{document}->line_count() : 1;
        my $gutter_width = Zepto::Renderer->get_gutter_width($line_count);
        my $visual_col = $x - $gutter_width - 1;  # -1 because terminal columns are 1-indexed

        if ($visual_col >= 0) {
            my $doc_line = $view->scroll_line() + $text_row;

            # Clamp line to document bounds
            $doc_line = 0 if $doc_line < 0;
            $doc_line = $self->{document}->line_count() - 1
                if $doc_line >= $self->{document}->line_count();

            # Convert visual column to document column, accounting for tabs
            # Need to add scroll_col to visual position first
            my $absolute_visual_col = $view->scroll_col() + $visual_col;
            my $line_content = $self->{document}->get_line($doc_line) // '';
            my $doc_col = Zepto::Renderer::visual_to_char_col($line_content, $absolute_visual_col);

            $view->set_cursor($doc_line, $doc_col, $shift);
        }
    }
    elsif ($action eq 'release') {
        # Track mouse button state
        $self->{mouse_button_down} = 0;
    }
    elsif ($action eq 'scroll') {
        if ($event->{button} eq 'up') {
            $view->move_up() for (1..3);
        }
        else {
            $view->move_down() for (1..3);
        }
    }
    elsif ($action eq 'drag') {
        # Only handle drag if mouse button is actually down
        # (some terminals send spurious motion events)
        return unless $self->{mouse_button_down};

        # Handle drag for selection
        my $text_row = $y - 3;  # Adjust for menu bar (row 1) and ruler bar (row 2)
        my $line_count = $self->{document} ? $self->{document}->line_count() : 1;
        my $gutter_width = Zepto::Renderer->get_gutter_width($line_count);
        my $visual_col = $x - $gutter_width - 1;  # -1 because terminal columns are 1-indexed

        if ($visual_col >= 0 && !$view->has_selection()) {
            # Start selection on first drag
            $view->set_cursor($view->cursor_line(), $view->cursor_col(), 1);
        }

        my $doc_line = $view->scroll_line() + $text_row;

        # Clamp line to document bounds
        $doc_line = 0 if $doc_line < 0;
        $doc_line = $self->{document}->line_count() - 1
            if $doc_line >= $self->{document}->line_count();

        # Convert visual column to document column, accounting for tabs
        my $absolute_visual_col = $view->scroll_col() + $visual_col;
        my $line_content = $self->{document}->get_line($doc_line) // '';
        my $doc_col = Zepto::Renderer::visual_to_char_col($line_content, $absolute_visual_col);

        # Extend selection
        $view->set_cursor($doc_line, $doc_col, 1) if $visual_col >= 0;
    }
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
    $self->{footer_input} = {
        prompt    => $opts{prompt} // '',
        value     => $opts{value} // '',
        cursor    => length($opts{value} // ''),
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

    my $input = $self->{footer_input};
    my $type = $event->{type};

    if ($type eq 'key') {
        my $key = $event->{key};

        if ($key eq 'enter') {
            my $value = $input->{value};
            my $callback = $input->{on_submit};
            $self->close_footer_input();
            $callback->($value) if $callback;
        }
        elsif ($key eq 'escape') {
            my $callback = $input->{on_cancel};
            $self->close_footer_input();
            $callback->() if $callback;
        }
        elsif ($key eq 'backspace') {
            if ($input->{cursor} > 0) {
                my $val = $input->{value};
                my $pos = $input->{cursor};
                $input->{value} = substr($val, 0, $pos - 1) . substr($val, $pos);
                $input->{cursor}--;
            }
        }
        elsif ($key eq 'delete') {
            if ($input->{cursor} < length($input->{value})) {
                my $val = $input->{value};
                my $pos = $input->{cursor};
                $input->{value} = substr($val, 0, $pos) . substr($val, $pos + 1);
            }
        }
        elsif ($key eq 'left') {
            $input->{cursor}-- if $input->{cursor} > 0;
        }
        elsif ($key eq 'right') {
            $input->{cursor}++ if $input->{cursor} < length($input->{value});
        }
        elsif ($key eq 'home') {
            $input->{cursor} = 0;
        }
        elsif ($key eq 'end') {
            $input->{cursor} = length($input->{value});
        }
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        unless (Zepto::InputParser::has_modifier($event, 'ctrl')) {
            my $val = $input->{value};
            my $pos = $input->{cursor};
            $input->{value} = substr($val, 0, $pos) . $char . substr($val, $pos);
            $input->{cursor}++;
        }
    }
}

# =============================================================================
# Incremental Find Handling
# =============================================================================

sub enter_find_mode {
    my ($self) = @_;
    $self->{state} = STATE_FIND;
    $self->{find_input} = $self->{search_term};  # Pre-fill with last search
    $self->{find_input_cursor} = length($self->{find_input});
    $self->{find_replace_input} = $self->{search_replace};  # Pre-fill replace too
    $self->{find_replace_cursor} = length($self->{find_replace_input});
    $self->{find_replace_active} = 1;  # Always show replace field
    $self->{find_focus} = 'find';
    $self->{find_replace_preview} = undef;  # Virtual preview data
    $self->{find_replaced} = [];      # Clear replaced highlights
    $self->_update_find_matches();
}

sub exit_find_mode {
    my ($self, $keep_changes) = @_;

    my $engine = $self->{find_engine};

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

    $self->{search_term} = $self->{find_input};  # Save for next time
    $self->{search_replace} = $self->{find_replace_input};  # Save replace too
    $self->{find_matches} = [];  # Clear highlights
    $self->{find_replaced} = [];  # Clear replaced highlights
    $self->{find_replace_preview} = undef;  # Clear virtual preview
    $self->{find_replace_active} = 0;
    $self->{state} = STATE_EDITING;
}

sub handle_find_event {
    my ($self, $event) = @_;

    my $type = $event->{type};

    # Determine which input field has focus
    my $in_replace = $self->{find_replace_active} && $self->{find_focus} eq 'replace';
    my ($val_ref, $cursor_ref) = $in_replace
        ? (\$self->{find_replace_input}, \$self->{find_replace_cursor})
        : (\$self->{find_input}, \$self->{find_input_cursor});

    if ($type eq 'key') {
        my $key = $event->{key};
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
        elsif ($key eq 'backspace') {
            if ($$cursor_ref > 0) {
                my $val = $$val_ref;
                my $pos = $$cursor_ref;
                $$val_ref = substr($val, 0, $pos - 1) . substr($val, $pos);
                $$cursor_ref--;
                if ($in_replace) {
                    $self->_apply_replace_preview() if $self->{find_replace_all};
                } else {
                    $self->_reset_replace_preview();  # Find term changed, reset preview
                    $self->_update_find_matches(1);  # Skip jump while typing
                }
            }
        }
        elsif ($key eq 'delete') {
            if ($$cursor_ref < length($$val_ref)) {
                my $val = $$val_ref;
                my $pos = $$cursor_ref;
                $$val_ref = substr($val, 0, $pos) . substr($val, $pos + 1);
                if ($in_replace) {
                    $self->_apply_replace_preview() if $self->{find_replace_all};
                } else {
                    $self->_reset_replace_preview();  # Find term changed, reset preview
                    $self->_update_find_matches(1);  # Skip jump while typing
                }
            }
        }
        elsif ($key eq 'left') {
            $$cursor_ref-- if $$cursor_ref > 0;
        }
        elsif ($key eq 'right') {
            $$cursor_ref++ if $$cursor_ref < length($$val_ref);
        }
        elsif ($key eq 'home') {
            $$cursor_ref = 0;
        }
        elsif ($key eq 'end') {
            $$cursor_ref = length($$val_ref);
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
                    $self->{find_replace_input} = $self->{find_input};
                    $self->{find_replace_cursor} = length($self->{find_replace_input});
                } elsif ($self->{find_focus} eq 'find') {
                    $self->{find_focus} = 'replace';
                } else {
                    $self->{find_focus} = 'find';
                }
            }
        }
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');

        if ($ctrl && lc($char) eq 'r') {
            # Ctrl+R: Toggle regex mode
            $self->{find_regex} = !$self->{find_regex};
            $self->_reset_replace_preview();
            $self->_update_find_matches(1);
        }
        elsif ($ctrl && lc($char) eq 'c') {
            # Ctrl+C: Toggle case-sensitive mode
            $self->{find_case} = !$self->{find_case};
            $self->_reset_replace_preview();
            $self->_update_find_matches(1);
        }
        elsif (!$ctrl) {
            my $val = $$val_ref;
            my $pos = $$cursor_ref;
            $$val_ref = substr($val, 0, $pos) . $char . substr($val, $pos);
            $$cursor_ref++;
            if ($in_replace) {
                $self->_apply_replace_preview() if $self->{find_replace_all};
            } else {
                $self->_reset_replace_preview();  # Find term changed, reset preview
                $self->_update_find_matches(1);  # Skip jump while typing
            }
        }
    }
}

# Handle clicks on the find bar (status bar in find mode)
sub handle_find_bar_click {
    my ($self, $x) = @_;

    # Compute click regions based on current state (must match _render_find_bar layout)
    my ($rows, $cols) = $self->{terminal}->get_size();

    # Calculate match text width
    my $match_count = $self->{find_engine} ? $self->{find_engine}->match_count() : 0;
    my $current = $self->{find_current} // 0;
    my $match_text = $match_count == 0
        ? (length($self->{find_input}) ? 'No matches' : '')
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
    }
    elsif ($x >= $replace_start && $x <= $replace_end) {
        $self->{find_focus} = 'replace';
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

# Reset replace preview state when find term changes
sub _reset_replace_preview {
    my ($self) = @_;

    # Clear virtual preview state (no buffer modification to undo!)
    $self->{find_replace_preview} = undef;
    $self->{find_replaced} = [];
}


sub _update_find_matches {
    my ($self, $skip_jump) = @_;
    my $doc = $self->{document};
    my $term = $self->{find_input};
    my $view = $self->{view};
    my $engine = $self->{find_engine};

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
    my $view = $self->{view};
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
    my $engine = $self->{find_engine};
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
    my $view = $self->{view};

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
    my $doc = $self->{document};
    my $replacement = $self->{find_replace_input};

    # Convert line/col to byte offset for document operations
    my $offset = $doc->line_col_to_offset($match->{line}, $match->{col});

    # Replace the match in the document
    $doc->replace($offset, $offset + $match->{length}, $replacement);

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

    my $doc = $self->{document};
    my $replacement = $self->{find_replace_input};
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
    my $result = '';
    my $last_end = 0;
    for my $m (@offsets) {
        # Add text between last match and this one
        $result .= substr($text, $last_end, $m->{offset} - $last_end);
        # Add replacement
        $result .= $replacement;
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

    my $doc = $self->{document};
    my $replacement = $self->{find_replace_input};

    # Sort by line/col descending to preserve offsets
    my @sorted = sort {
        $b->{line} <=> $a->{line} ||
        $b->{col} <=> $a->{col}
    } @$matches;

    for my $match (@sorted) {
        my $offset = $doc->line_col_to_offset($match->{line}, $match->{col});
        $doc->replace($offset, $offset + $match->{length}, $replacement);
    }

    # Update matches
    $self->_update_find_matches();

    my $count = scalar @sorted;
    $self->{message} = "Replaced $count occurrence" . ($count == 1 ? '' : 's');
    $self->{message_time} = time();
}

sub _apply_replace_preview {
    my ($self) = @_;

    my $view = $self->{view};
    my $engine = $self->{find_engine};
    my $replacement = $self->{find_replace_input};

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

sub open_file_picker {
    my ($self, %opts) = @_;

    my $base_dir = $opts{base_dir} // '.';

    $self->{state} = STATE_FILE_PICKER;
    $self->{file_picker} = Zepto::FilePicker->new(
        base_dir  => $base_dir,
        on_select => $opts{on_select},
        on_cancel => $opts{on_cancel},
    );
}

sub close_file_picker {
    my ($self) = @_;
    $self->{state} = STATE_EDITING;
    $self->{file_picker} = undef;
}

sub handle_file_picker_event {
    my ($self, $event) = @_;

    my $picker = $self->{file_picker};
    return unless $picker;

    my $type = $event->{type};

    if ($type eq 'key') {
        my $key = $event->{key};

        if ($key eq 'escape') {
            $picker->cancel();
            $self->close_file_picker();
        }
        elsif ($key eq 'enter') {
            $picker->confirm();
            $self->close_file_picker();
        }
        elsif ($key eq 'up') {
            $picker->move_up();
        }
        elsif ($key eq 'down') {
            $picker->move_down();
        }
        elsif ($key eq 'page_up') {
            my ($rows, $cols) = $self->{terminal}->get_size();
            my $visible = $rows - RESERVED_ROWS - 2;  # -2 for picker header
            $picker->page_up($visible);
        }
        elsif ($key eq 'page_down') {
            my ($rows, $cols) = $self->{terminal}->get_size();
            my $visible = $rows - RESERVED_ROWS - 2;
            $picker->page_down($visible);
        }
        elsif ($key eq 'backspace') {
            $picker->backspace();
        }
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        unless (Zepto::InputParser::has_modifier($event, 'ctrl')) {
            $picker->append_char($char);
        }
    }
    elsif ($type eq 'mouse') {
        $self->_handle_file_picker_mouse($event);
    }
}

sub _handle_file_picker_mouse {
    my ($self, $event) = @_;

    my $picker = $self->{file_picker};
    return unless $picker;

    my $action = $event->{action};
    my $x = $event->{x};
    my $y = $event->{y};

    # Calculate which row was clicked
    # Row 1 = menu bar, Row 2 = search input, Row 3 = separator, Row 4+ = file list
    my $list_start_row = 4;
    my ($rows, $cols) = $self->{terminal}->get_size();
    my $list_end_row = $rows - 1;  # -1 for status bar

    if ($action eq 'press') {
        if ($y >= $list_start_row && $y < $list_end_row) {
            my $list_index = ($y - $list_start_row) + $picker->scroll();
            my $max = $picker->filtered_count() - 1;
            if ($list_index >= 0 && $list_index <= $max) {
                $picker->select_index($list_index);
                $picker->confirm();
                $self->close_file_picker();
            }
        }
    }
    elsif ($action eq 'scroll_up') {
        $picker->move_up();
    }
    elsif ($action eq 'scroll_down') {
        $picker->move_down();
    }
}

# =============================================================================
# Editing Commands
# =============================================================================

sub do_insert_char {
    my ($self, $char) = @_;

    my $doc = $self->{document};
    my $view = $self->{view};

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

    my $doc = $self->{document};
    my $view = $self->{view};

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

    my $doc = $self->{document};
    my $view = $self->{view};

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

    my $doc = $self->{document};
    my $view = $self->{view};

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

    # Move to start of new line (after indent)
    $view->move_down();
    $view->move_to_line_start();
    $view->move_right() for (1..length($indent));
}

sub do_indent {
    my ($self) = @_;

    my $doc = $self->{document};
    my $view = $self->{view};

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

    my $doc = $self->{document};
    my $view = $self->{view};
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

    my $doc = $self->{document};
    my $view = $self->{view};

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

sub _duplicate_lines {
    my ($self, $direction) = @_;  # -1 = up, 1 = down

    my $doc = $self->{document};
    my $view = $self->{view};

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

    my $doc = $self->{document};
    my $view = $self->{view};

    return unless $view->has_selection();

    my ($start, $end) = $view->selection_offsets();
    $doc->delete($start, $end - $start);

    my ($line, $col) = $doc->offset_to_line_col($start);
    $view->clear_selection();
    $view->set_cursor($line, $col);
}

# =============================================================================
# Rendering
# =============================================================================

sub render {
    my ($self) = @_;

    my $term = $self->{terminal};
    my ($rows, $cols) = $term->get_size();

    # Update view size - account for gutter width
    my $line_count = $self->{document}->line_count();
    my $gutter_width = Zepto::Renderer->get_gutter_width($line_count);
    my $text_width = $cols - $gutter_width;
    $text_width = Zepto::Renderer::MIN_TEXT_WIDTH if $text_width < Zepto::Renderer::MIN_TEXT_WIDTH;

    $self->{view}->set_viewport_size($rows - RESERVED_ROWS, $text_width);
    $self->{view}->ensure_cursor_visible();

    my $output = Zepto::Renderer->render(
        document    => $self->{document},
        view        => $self->{view},
        theme       => $self->{theme},
        prefs       => $self->{prefs},
        rows        => $rows,
        cols        => $cols,
        message     => $self->{message},
        highlighter => $self->{highlighter},
        ui          => {
            menu_open => $self->{menu_open},
            menu_selected => $self->{menu_selected},
            dialog => $self->{dialog},
            prompt => $self->{prompt},
            footer_input => $self->{footer_input},
            file_picker => $self->{file_picker},
            find_mode => ($self->{state} eq STATE_FIND) ? {
                value          => $self->{find_input},
                cursor         => $self->{find_input_cursor},
                matches        => $self->{find_matches},
                replaced       => $self->{find_replaced},
                replace_preview => $self->{find_replace_preview},  # Virtual preview data
                current        => $self->{find_current},
                regex          => $self->{find_regex},
                case           => $self->{find_case},
                replace_value  => $self->{find_replace_input},
                replace_cursor => $self->{find_replace_cursor},
                replace_active => $self->{find_replace_active},
                replace_all    => $self->{find_replace_all},
                focus          => $self->{find_focus},
                match_count    => $self->{find_engine} ? $self->{find_engine}->match_count() : 0,
                is_searching   => $self->{find_engine} ? $self->{find_engine}->is_searching() : 0,
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
    $self->{message_time} = time();
}

1;
