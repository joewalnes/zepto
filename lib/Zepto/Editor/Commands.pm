package Zepto::Editor::Commands;
# =============================================================================
# Editor Commands - File, Edit, Search, View operations
# =============================================================================
#
# This module defines command methods for the Zepto::Editor class.
# Commands are user-facing operations like save, quit, undo, find, etc.
# =============================================================================

use strict;
use warnings;

# Define methods in Zepto::Editor's namespace
package Zepto::Editor;
use IO::Select;
use POSIX qw(WNOHANG setpgid);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use Time::HiRes qw(time);

# Check if editor is in a modal input state (footer_input, prompt, find, dialog)
sub _in_modal_state {
    my ($self) = @_;
    my $s = $self->{state};
    return $s eq 'footer_input' || $s eq 'prompt' || $s eq 'find' || $s eq 'dialog';
}

use Zepto::Theme;
use Zepto::FileSearchEngine;

# Strip Perl internals from $@ to produce a user-friendly error message.
# "Permission denied at lib/Zepto/Document.pm line 142.\n" -> "Permission denied"
sub _user_error {
    my ($action, $err) = @_;
    $err //= 'Unknown error';
    $err =~ s/\s+at\s+\S+\s+line\s+\d+.*//s;
    chomp $err;
    return "$action: $err";
}

# =============================================================================
# File Commands
# =============================================================================

sub cmd_save {
    my ($self) = @_;

    my $doc = $self->active_doc();

    unless ($doc->path()) {
        # Need to get filename - use footer input (in status bar)
        $self->open_footer_input(
            prompt => 'Save As:',
            on_submit => sub {
                my ($filename) = @_;
                if ($filename) {
                    $doc->set_path($filename);
                    eval { $doc->save(); };
                    if ($@) {
                        $self->show_error_message(_user_error("Save failed", $@));
                    }
                    else {
                        # Update tab's file_path and clear untitled name
                        my $tab = $self->active_tab();
                        $tab->{file_path} = $filename;
                        $tab->{untitled_name} = undef;
                        # Re-detect syntax highlighting for the new filename
                        $self->active_highlighter()->set_file($filename);
                        $self->show_message("Saved: $filename");
                        # Refresh file tree to show newly saved file
                        if ($self->{file_tree}) {
                            $self->{file_tree}->refresh();
                        }
                    }
                }
            },
            on_cancel => sub {
                $self->show_message("Save cancelled");
            },
        );
        return;
    }

    eval { $doc->save(); };
    if ($@) {
        $self->show_error_message(_user_error("Save failed", $@));
    }
    else {
        $self->show_message("Saved: " . $doc->filename());
    }
}

sub cmd_close_tab {
    my ($self) = @_;

    my $doc = $self->active_doc();

    # Save if dirty, then close. No prompt — Ctrl+Q prompts instead.
    if ($doc->is_dirty()) {
        $self->cmd_save();
        # Only close if save succeeded
        return if $self->active_doc()->is_dirty();
    }
    $self->_do_close_tab($self->{tab_manager}->active_index());
}

sub _do_close_tab {
    my ($self, $index) = @_;
    my $tm = $self->{tab_manager};

    # Save cursor position before closing
    my $tab = $tm->tab_at($index);
    if ($tab && $tab->{view} && $tab->{file_path}) {
        my $view = $tab->{view};
        $self->_save_cursor_position(
            $tab->{file_path},
            $view->cursor_line(),
            $view->cursor_col(),
        );
    }

    # If this is the last tab, quit
    if ($tm->tab_count() <= 1) {
        $self->{state} = 'quit';
        return;
    }

    # Get MRU previous before removal
    my $mru_prev = $tm->mru_previous();

    # Remove the tab
    $tm->remove_tab($index);

    # Restore find state from the new active tab
    $self->_restore_find_state_from_tab();
}

sub cmd_quit {
    my ($self) = @_;
    my $tm = $self->{tab_manager};

    # Save cursor positions for all open tabs
    for my $i (0 .. $tm->tab_count() - 1) {
        my $tab = $tm->tab_at($i);
        if ($tab && $tab->{view} && $tab->{file_path}) {
            $self->_save_cursor_position(
                $tab->{file_path},
                $tab->{view}->cursor_line(),
                $tab->{view}->cursor_col(),
            );
        }
    }

    # Collect indices of dirty tabs
    my @dirty;
    for my $i (0 .. $tm->tab_count() - 1) {
        my $tab = $tm->tab_at($i);
        if ($tab->{document} && $tab->{document}->is_dirty()) {
            push @dirty, $i;
        }
    }

    # If no dirty tabs, quit immediately
    unless (@dirty) {
        $self->{state} = 'quit';
        return;
    }

    # Walk through dirty tabs one at a time
    $self->_prompt_close_dirty_tabs(\@dirty, sub {
        $self->{state} = 'quit';
    });
}

sub _prompt_close_dirty_tabs {
    my ($self, $dirty_indices, $on_all_done) = @_;

    return $on_all_done->() unless @$dirty_indices;

    my $index = shift @$dirty_indices;
    my $tm = $self->{tab_manager};

    # Switch to the dirty tab
    $self->_switch_to_tab($index);

    my $tab = $tm->tab_at($index);
    my $name = $tab->{untitled_name}
            || ($tab->{document} ? $tab->{document}->filename() : undef)
            || '[untitled]';

    my $save_icon = Zepto::Chars->get('save');
    my $times_icon = Zepto::Chars->get('times');
    $self->open_prompt(
        text => "Save changes to $name?",
        options => [
            { key => 'y', label => 'Save', icon => $save_icon },
            { key => 'n', label => 'Discard', icon => $times_icon },
            { key => 'c', label => 'Cancel' },
        ],
        on_select => sub {
            my ($choice) = @_;
            if ($choice eq 'y') {
                $self->cmd_save();
                if ($self->active_doc()->is_dirty()) {
                    return;  # Save failed, stay on this tab
                }
                # Continue to next dirty tab
                $self->_prompt_close_dirty_tabs($dirty_indices, $on_all_done);
            }
            elsif ($choice eq 'n') {
                # Discard and continue
                $self->_prompt_close_dirty_tabs($dirty_indices, $on_all_done);
            }
            # 'c' = cancel entire quit
        },
    );
}

sub cmd_new_file {
    my ($self) = @_;

    # Create new tab (no dirty check needed - we're not replacing anything)
    my ($doc, $view, $find_engine, $highlighter) = $self->_create_document_state(undef);
    my $untitled_name = $self->{tab_manager}->next_untitled_name();

    $self->{tab_manager}->add_tab(
        document      => $doc,
        view          => $view,
        find_engine   => $find_engine,
        highlighter   => $highlighter,
        file_path     => undef,
        untitled_name => $untitled_name,
    );
}

sub cmd_open_file {
    my ($self) = @_;

    # Open palette in files mode
    $self->{state} = 'palette';
    $self->{palette_mode} = 'files';
    $self->{palette_widget} = Zepto::InputWidget->new();
    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->_palette_update_filtered();
}

sub cmd_recent_files {
    my ($self) = @_;

    my @recent = @{$self->{_recent_files} || []};
    unless (@recent) {
        $self->show_message("No recent files");
        return;
    }

    # Open palette in recent_files mode
    $self->{state} = 'palette';
    $self->{palette_mode} = 'recent_files';
    $self->{palette_widget} = Zepto::InputWidget->new();
    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->_palette_update_filtered();
}

sub _load_file {
    my ($self, $path) = @_;

    # Record location before switching files
    $self->_record_location();

    # Track in recent files
    $self->_track_recent_file($path);

    # Unfocus file tree so document gets focus after opening
    if ($self->{file_tree} && $self->{file_tree}->focused()) {
        $self->{file_tree}->set_focused(0);
    }

    # Check if file is already open in another tab
    my $existing = $self->{tab_manager}->find_tab_by_path($path);
    if (defined $existing) {
        $self->_switch_to_tab($existing);
        return;
    }

    # Check if current tab is an empty untitled tab before opening new file
    my $prev_idx = $self->{tab_manager}->active_index();
    my $close_idx = $self->_empty_untitled_tab_index($prev_idx);

    eval {
        my ($doc, $view, $find_engine, $highlighter) = $self->_create_document_state($path);
        $self->{tab_manager}->add_tab(
            document    => $doc,
            view        => $view,
            find_engine => $find_engine,
            highlighter => $highlighter,
            file_path   => $path,
        );
        # Restore cursor position from history
        $self->_restore_cursor_position($path, $view);
        if ($doc->{_is_binary}) {
            $self->show_message("Binary file — read only");
        }
    };
    if ($@) {
        $self->show_error_message(_user_error("Could not open file", $@));
        return;
    }

    # Close the previous empty untitled tab now that new file is open
    if (defined $close_idx) {
        $self->{tab_manager}->remove_tab($close_idx);
    }

    # Reveal the newly opened file in the file tree
    if ($self->{file_tree} && !$self->{file_tree}->focused()) {
        $self->{file_tree}->set_current_file($path);
        $self->{file_tree}->expand_to_path($path);
    }
}

# =============================================================================
# Edit Commands
# =============================================================================

sub cmd_undo {
    my ($self) = @_;
    if ($self->active_doc()->undo()) {
        $self->show_message("Undo");
        # Re-trigger completion if cursor is now at a word character
        $self->_retrigger_completion_if_word();
    }
    else {
        $self->show_message("Nothing to undo");
    }
}

sub cmd_redo {
    my ($self) = @_;
    if ($self->active_doc()->redo()) {
        $self->show_message("Redo");
        $self->_retrigger_completion_if_word();
    }
    else {
        $self->show_message("Nothing to redo");
    }
}

# Clipboard helpers — tag the hang watchdog around the external clipboard
# command, same idea as the transform pump: this is already independently
# timeout-protected (Terminal.pm), but tagging gives a diagnostic log
# something more useful than "loop" to report if it ever wedges anyway.
sub _clipboard_copy {
    my ($self, $text) = @_;
    Zepto::HangWatchdog::heartbeat($self->{_watchdog}, 'clipboard:copy');
    $self->{terminal}->copy_to_clipboard($text);
    Zepto::HangWatchdog::heartbeat($self->{_watchdog}, 'loop');
}

sub _clipboard_paste {
    my ($self) = @_;
    Zepto::HangWatchdog::heartbeat($self->{_watchdog}, 'clipboard:paste');
    my $text = $self->{terminal}->paste_from_clipboard();
    Zepto::HangWatchdog::heartbeat($self->{_watchdog}, 'loop');
    return $text;
}

sub cmd_cut {
    my ($self) = @_;

    my $view = $self->active_view();

    # Column selection: copy rectangle then delete
    if ($view->column_select() && $view->has_selection()) {
        my $lines = $view->column_selected_text();
        $self->{clipboard} = join("\n", @$lines);
        $self->{clipboard_columnar} = 1;
        $self->_clipboard_copy($self->{clipboard});
        $self->delete_selection();
        $self->show_message("Cut " . scalar(@$lines) . " lines (column)");
        return;
    }

    # If no selection, select current line first
    $view->select_line() unless $view->has_selection();

    if ($view->has_selection()) {
        $self->{clipboard} = $view->selected_text();
        $self->{clipboard_columnar} = 0;
        $self->_clipboard_copy($self->{clipboard});
        $self->delete_selection();
        $self->show_message("Cut");
    }
}

sub cmd_copy {
    my ($self) = @_;

    my $view = $self->active_view();
    my $doc = $self->active_doc();

    # Column selection: copy rectangle
    if ($view->column_select() && $view->has_selection()) {
        my $lines = $view->column_selected_text();
        $self->{clipboard} = join("\n", @$lines);
        $self->{clipboard_columnar} = 1;
        $self->_clipboard_copy($self->{clipboard});
        $self->show_message("Copied " . scalar(@$lines) . " lines (column)");
        return;
    }

    # If no selection, copy current line (including newline if not last line)
    unless ($view->has_selection()) {
        my $line = $view->cursor_line();
        my $content = $doc->get_line_content($line);

        # Add newline if not the last line
        if ($line < $doc->line_count() - 1) {
            $content .= "\n";
        }

        $self->{clipboard} = $content;
        $self->{clipboard_columnar} = 0;
        $self->_clipboard_copy($self->{clipboard});

        # Select the line visually (cursor stays at end of line)
        my $line_len = $doc->line_length($line);
        $view->set_cursor($line, 0, 0);        # Start of line, no extend
        $view->set_cursor($line, $line_len, 1); # End of line, extend selection

        $self->show_message("Copied line");
        return;
    }

    $self->{clipboard} = $view->selected_text();
    $self->{clipboard_columnar} = 0;
    $self->_clipboard_copy($self->{clipboard});
    $self->show_message("Copied");
}

sub cmd_paste {
    my ($self) = @_;

    # Try system clipboard first, fall back to internal clipboard
    my $text = $self->_clipboard_paste();
    if (length $text) {
        $self->{clipboard} = $text;
        $self->{clipboard_columnar} = 0;  # System clipboard is always linear
    }

    return unless length $self->{clipboard};

    my $doc = $self->active_doc();
    my $view = $self->active_view();

    # Columnar paste (from column copy/cut or into column selection)
    if ($self->{clipboard_columnar} || $view->column_select()) {
        $self->_column_paste($self->{clipboard});
        return;
    }

    # Delete selection first
    if ($view->has_selection()) {
        $self->delete_selection();
    }

    my $offset = $doc->line_col_to_offset(
        $view->cursor_line(),
        $view->cursor_col()
    );

    $doc->insert($offset, $self->{clipboard});

    # Move cursor to end of pasted text
    my $end_offset = $offset + length($self->{clipboard});
    my ($line, $col) = $doc->offset_to_line_col($end_offset);
    $view->set_cursor($line, $col);

    $self->show_message("Pasted");
}

# Paste text in column (vertical) mode
sub _column_paste {
    my ($self, $text) = @_;
    my $doc = $self->active_doc();
    my $view = $self->active_view();

    my @paste_lines = split(/\n/, $text, -1);
    # Remove trailing empty element from split if text ended with newline
    pop @paste_lines if @paste_lines > 1 && $paste_lines[-1] eq '';

    $doc->begin_undo_group();

    # Delete existing column selection content if any
    my $start_col;
    my $start_line;
    if ($view->column_select() && $view->has_selection()) {
        my ($top, $left, $bottom, $right) = $view->column_selection();
        $start_line = $top;
        $start_col = $left;

        if ($left != $right) {
            # Delete rectangle content bottom-to-top
            for my $ln (reverse $top .. $bottom) {
                my $line_len = $doc->line_length($ln);
                next if $line_len <= $left;
                my $del_end = $right < $line_len ? $right : $line_len;
                my $del_len = $del_end - $left;
                next if $del_len <= 0;
                my $offset = $doc->line_col_to_offset($ln, $left);
                $doc->delete($offset, $del_len);
            }
        }
    } else {
        $start_line = $view->cursor_line();
        $start_col = $view->cursor_col();
    }

    # Single-line paste with column selection: replicate on each line
    my $num_target_lines;
    if ($view->column_select() && $view->has_selection()) {
        my ($top, $left, $bottom, $right) = $view->column_selection();
        $num_target_lines = $bottom - $top + 1;
    } else {
        $num_target_lines = scalar @paste_lines;
    }

    for my $i (reverse 0 .. $num_target_lines - 1) {
        my $target_line = $start_line + $i;
        # Skip (not abort) rows past the end of the document. This loop
        # walks target lines bottom-to-top (reverse), so the highest $i is
        # checked first — using `last` here would bail out of the whole
        # paste the moment the bottom-most row didn't fit, silently
        # discarding every valid row above it (e.g. pasting a 3-row column
        # onto the last line of the document pasted nothing at all).
        next if $target_line >= $doc->line_count();

        # Use corresponding paste line, or replicate single line
        my $paste_text = @paste_lines == 1 ? $paste_lines[0]
                       : $i < @paste_lines ? $paste_lines[$i]
                       : '';

        my $line_len = $doc->line_length($target_line);
        # Pad if line is shorter than insertion point
        if ($line_len < $start_col) {
            my $pad = ' ' x ($start_col - $line_len);
            my $offset = $doc->line_col_to_offset($target_line, $line_len);
            $doc->insert($offset, $pad);
        }

        my $offset = $doc->line_col_to_offset($target_line, $start_col);
        $doc->insert($offset, $paste_text);
    }

    $doc->end_undo_group();

    $view->clear_selection();
    my $paste_len = CORE::length($paste_lines[0] // '');
    $view->set_cursor($start_line, $start_col + $paste_len);
    $self->show_message("Pasted (column)");
}

sub cmd_select_all {
    my ($self) = @_;
    my $view = $self->active_view();
    $view->exit_column_mode() if $view->column_select();
    $view->select_all();
}

# =============================================================================
# Multi-Cursor Commands
# =============================================================================

sub cmd_select_next_occurrence {
    my ($self) = @_;

    my $view = $self->active_view();
    my $doc = $self->active_doc();
    return unless $view && $doc;

    # If no selection, select word under cursor first
    if (!$view->has_selection()) {
        $view->select_word();
        return unless $view->has_selection();
        # Store the search term for subsequent presses
        $self->{_multi_cursor_term} = $view->selected_text();
        return;
    }

    # Get the selected text (this is what we're searching for)
    my $term = $view->selected_text();
    return unless length($term);

    # If the term changed (user manually selected something different), reset
    if (!defined $self->{_multi_cursor_term} || $self->{_multi_cursor_term} ne $term) {
        $self->{_multi_cursor_term} = $term;
        $view->clear_multi_cursors();
    }

    # Find the next occurrence after the last cursor position
    my $text = $doc->text();
    my $term_len = length($term);
    my $term_quoted = quotemeta($term);

    # Collect all existing cursor end positions to find where to search from
    my @cursors = $view->all_cursors_sorted();
    my $last = $cursors[-1];
    my $search_from_offset = $doc->line_col_to_offset($last->{line}, $last->{col});

    # Search forward from the last cursor, wrapping around
    my $found_offset = index($text, $term, $search_from_offset);
    if ($found_offset < 0) {
        # Wrap to beginning
        $found_offset = index($text, $term, 0);
    }

    if ($found_offset >= 0) {
        my ($found_line, $found_col) = $doc->offset_to_line_col($found_offset);
        my $end_col = $found_col + $term_len;

        # Handle match spanning line boundary (term contains newline) — skip
        # For simplicity, only handle single-line matches
        my $line_content = $doc->get_line_content($found_line);
        if ($found_col + $term_len <= length($line_content)) {
            # Check if this position already has a cursor
            if (!$view->has_cursor_at($found_line, $end_col)) {
                # Save the current primary cursor as a secondary cursor
                $view->add_multi_cursor(
                    line        => $view->cursor_line(),
                    col         => $view->cursor_col(),
                    anchor_line => $view->{selection_anchor_line},
                    anchor_col  => $view->{selection_anchor_col},
                );

                # Move primary cursor to the new occurrence
                $view->{selection_anchor_line} = $found_line;
                $view->{selection_anchor_col}  = $found_col;
                $view->{cursor_line} = $found_line;
                $view->{cursor_col}  = $end_col;
                $view->{_preferred_col} = $end_col;

                # Ensure the new cursor is visible
                $view->ensure_cursor_visible();

                my $count = $view->cursor_count();
                $self->show_message("$count cursors");
            } else {
                $self->show_message("All occurrences selected");
            }
        }
    } else {
        $self->show_message("No more occurrences");
    }
}

# Search Commands
# =============================================================================

sub cmd_find {
    my ($self) = @_;
    $self->enter_find_mode();
}

sub cmd_find_replace {
    my ($self) = @_;
    $self->enter_find_mode(replace => 1);
}

sub cmd_find_next {
    my ($self) = @_;

    if ($self->{search_term}) {
        $self->_record_location();
        # Enter find mode and navigate to next match
        $self->enter_find_mode();
        $self->_find_navigate(1);
    }
    else {
        $self->cmd_find();
    }
}

sub cmd_find_prev {
    my ($self) = @_;

    if ($self->{search_term}) {
        $self->_record_location();
        # Enter find mode and navigate to prev match
        $self->enter_find_mode();
        $self->_find_navigate(-1);
    }
    else {
        $self->cmd_find();
    }
}

sub do_find_next {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();
    my $term = $self->{search_term};

    return unless $term;

    my $text = $doc->text();
    my $start = $doc->line_col_to_offset(
        $view->cursor_line(),
        $view->cursor_col()
    ) + 1;

    my $pos = index($text, $term, $start);

    # Wrap around
    if ($pos == -1 && $self->{prefs}->search_wrap()) {
        $pos = index($text, $term, 0);
    }

    if ($pos >= 0) {
        my ($line, $col) = $doc->offset_to_line_col($pos);
        $view->set_cursor($line, $col);
        # Select the match
        $view->set_cursor($line, $col + length($term), 1);
        $self->show_message("Found");
    }
    else {
        $self->show_message("Not found: $term");
    }
}

sub do_find_prev {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $view = $self->active_view();
    my $term = $self->{search_term};

    return unless $term;

    my $text = $doc->text();

    # When there's a selection, search from BEFORE the selection start
    # Otherwise we'd be stuck finding the same match over and over
    my $end;
    if ($view->has_selection()) {
        my ($start_offset, $end_offset) = $view->selection_offsets();
        $end = $start_offset - 1;
    }
    else {
        $end = $doc->line_col_to_offset(
            $view->cursor_line(),
            $view->cursor_col()
        ) - 1;
    }

    my $pos = rindex($text, $term, $end);

    # Wrap around
    if ($pos == -1 && $self->{prefs}->search_wrap()) {
        $pos = rindex($text, $term);
    }

    if ($pos >= 0) {
        my ($line, $col) = $doc->offset_to_line_col($pos);
        $view->set_cursor($line, $col);
        # Select the match
        $view->set_cursor($line, $col + length($term), 1);
        $self->show_message("Found");
    }
    else {
        $self->show_message("Not found: $term");
    }
}

sub cmd_find_in_files {
    my ($self) = @_;

    # Lazily init FileSearchEngine
    if (!$self->{_file_search_engine}) {
        $self->{_file_search_engine} = Zepto::FileSearchEngine->new();
    }
    $self->{_file_search_engine}->detect_backend(Cwd::getcwd());

    # Set default scope to project root (only on first open)
    if (!defined $self->{_file_search_scope}) {
        $self->{_file_search_scope} = Cwd::getcwd();
        $self->{_file_search_scope_label} = 'project';
    }

    # Open palette in find_in_files mode
    $self->{state} = 'palette';
    $self->{palette_mode} = 'find_in_files';

    # Restore previous widget if available, with text selected for easy replacement
    if ($self->{_file_search_saved_widget} && length($self->{_file_search_saved_widget}->value())) {
        $self->{palette_widget} = $self->{_file_search_saved_widget};
        # Select all text so typing replaces it immediately
        $self->{palette_widget}->{sel_start} = 0;
        $self->{palette_widget}->{sel_end} = length($self->{palette_widget}->value());
        $self->{palette_widget}->{cursor} = length($self->{palette_widget}->value());
        # Restore cursor position in results list
        $self->{palette_cursor} = $self->{_file_search_saved_cursor} // 0;
        $self->{palette_scroll} = $self->{_file_search_saved_scroll} // 0;
    } else {
        $self->{palette_widget} = Zepto::InputWidget->new();
        $self->{palette_cursor} = 0;
        $self->{palette_scroll} = 0;
    }

    $self->_palette_update_filtered();
}

sub cmd_goto_line {
    my ($self) = @_;

    my $view = $self->active_view();
    my $current_line = $view->cursor_line();
    my $current_col  = $view->cursor_col();
    my $prefill = ($current_line + 1) . ':' . ($current_col + 1);

    $self->open_footer_input(
        prompt => '',
        value  => $prefill,
        select_all => 1,
        hint => 'line, line:col, or :col',
        id   => 'goto_line',
        on_submit => sub {
            my ($input) = @_;
            return unless defined $input && $input =~ /\S/;

            my ($line, $col);

            if ($input =~ /^:(\d+)$/) {
                # :col - jump to column on current line
                $line = $current_line;
                $col = $1 - 1;  # Convert to 0-indexed
            }
            elsif ($input =~ /^(\d+):(\d+)$/) {
                # line:col - jump to specific line and column
                $line = $1 <= 0 ? 0 : $1 - 1;  # 0 or negative -> line 0
                $col = $2 - 1;  # Convert to 0-indexed
            }
            elsif ($input =~ /^(\d+)$/) {
                # line only
                $line = $1 <= 0 ? 0 : $1 - 1;  # 0 or negative -> line 0
                $col = 0;
            }
            else {
                $self->{status_msg} = "Invalid format. Use: line, line:col, or :col";
                return;
            }

            # Clamp line to valid range
            my $max_line = $self->active_doc()->line_count() - 1;
            $line = 0 if $line < 0;
            $line = $max_line if $line > $max_line;

            # Clamp column to line length
            $col = 0 if $col < 0;
            my $max_col = $self->active_doc()->line_length($line);
            $col = $max_col if $col > $max_col;

            $self->_record_location();
            $self->active_view()->set_cursor($line, $col);
        },
    );
}

# =============================================================================
# Toggle Line Comment
# =============================================================================

sub cmd_toggle_comment {
    my ($self) = @_;

    my $doc  = $self->active_doc();
    my $view = $self->active_view();
    my $hl   = $self->active_highlighter();

    return unless $hl && $hl->{grammar};

    # Determine line range
    my ($start_line, $end_line);
    if ($view->has_selection()) {
        my ($sl, $sc, $el, $ec) = $view->selection();
        $start_line = $sl;
        $end_line   = $el;
        # If selection ends at col 0 of a line, don't include that line
        $end_line = $el - 1 if $ec == 0 && $el > $sl;
    } else {
        $start_line = $view->cursor_line();
        $end_line   = $start_line;
    }

    # Get context-aware comment style (uses line state for HTML/embedded langs)
    my $line_state = $hl->line_start_state($start_line);
    my $style = $hl->{grammar}->comment_style($line_state);
    return unless defined $style;  # No comment syntax for this language/context

    my $prefix = $style->{prefix};
    my $suffix = $style->{suffix};  # undef for line-prefix comments

    # Check if ALL non-blank lines in range are commented
    my $all_commented = 1;
    my $prefix_re = quotemeta($prefix);
    my $suffix_re = defined $suffix ? quotemeta($suffix) : '';
    for my $ln ($start_line .. $end_line) {
        my $content = $doc->get_line_content($ln);
        next if $content =~ /^\s*$/;  # skip blank lines
        if (defined $suffix) {
            # Block comment: must have both prefix and suffix
            unless ($content =~ /^\s*$prefix_re/ && $content =~ /$suffix_re\s*$/) {
                $all_commented = 0;
                last;
            }
        } else {
            unless ($content =~ /^\s*$prefix_re/) {
                $all_commented = 0;
                last;
            }
        }
    }

    # Find the minimum indentation across non-blank lines (for aligned commenting)
    my $min_indent = undef;
    if (!$all_commented) {
        for my $ln ($start_line .. $end_line) {
            my $content = $doc->get_line_content($ln);
            next if $content =~ /^\s*$/;
            if ($content =~ /^(\s*)/) {
                my $indent_len = length($1);
                $min_indent = $indent_len if !defined($min_indent) || $indent_len < $min_indent;
            }
        }
        $min_indent //= 0;
    }

    # Apply: process lines from bottom to top so offsets don't shift
    for my $ln (reverse $start_line .. $end_line) {
        my $content = $doc->get_line_content($ln);
        my $line_start = $doc->line_start_offset($ln);

        if ($all_commented) {
            if (defined $suffix) {
                # Uncomment block: remove suffix first (higher offset), then prefix
                if ($content =~ / ?$suffix_re(\s*)$/) {
                    my $trail_len = length($1);
                    my $match_start = $-[0];
                    my $match_len = length($&) - $trail_len;
                    $doc->replace($line_start + $match_start, $line_start + $match_start + $match_len, '');
                }
                # Re-read content after suffix removal for prefix removal
                $content = $doc->get_line_content($ln);
                if ($content =~ /^(\s*)$prefix_re ?/) {
                    my $indent_len = length($1);
                    my $match_len = length($&) - $indent_len;
                    $doc->replace($line_start + $indent_len, $line_start + $indent_len + $match_len, '');
                }
            } else {
                # Uncomment line-prefix: remove prefix and optional trailing space
                if ($content =~ /^(\s*)$prefix_re ?/) {
                    my $indent_len = length($1);
                    my $match_len = length($&) - $indent_len;
                    my $replace_start = $line_start + $indent_len;
                    $doc->replace($replace_start, $replace_start + $match_len, '');
                }
            }
        } else {
            next if $content =~ /^\s*$/;  # skip blank lines
            if (defined $suffix) {
                # Comment block: insert suffix at end first, then prefix at indent
                my $line_end = $line_start + length($content);
                $doc->replace($line_end, $line_end, " $suffix");
                my $insert_pos = $line_start + $min_indent;
                $doc->replace($insert_pos, $insert_pos, "$prefix ");
            } else {
                # Comment line-prefix: insert prefix at min_indent position
                my $insert_pos = $line_start + $min_indent;
                $doc->replace($insert_pos, $insert_pos, "$prefix ");
            }
        }
    }

    # Invalidate wrap map
    $view->invalidate_wrap_map();
}

# Wait for $pid to exit, up to $grace seconds, without ever blocking
# indefinitely. If it hasn't exited on its own within that window, kill it
# (and its process group) and reap synchronously. Shared by every
# subprocess call site in this file that needs a bounded wait — both
# "we're deliberately killing this on timeout" and "both pipes hit EOF,
# but that doesn't guarantee the process itself has exited yet" (e.g. a
# daemonizing helper, or something that dup2'd its fds away and kept
# running) need this; a bare `waitpid($pid, 0)` in either case would
# reintroduce the exact class of hang this whole pump exists to prevent.
sub _bounded_reap {
    my ($pid, $grace) = @_;
    $grace //= 1;

    if ($grace > 0) {
        my $deadline = time() + $grace;
        while (time() < $deadline) {
            my $ret = waitpid($pid, WNOHANG);
            return 1 if $ret == $pid;
            select(undef, undef, undef, 0.05);
        }
    }

    # Still not reaped after the grace period (or none was requested —
    # caller already knows this needs killing, e.g. a timeout) — force it.
    # Signal both the pid and its process group: `sh -c $cmd` may have
    # spawned a pipeline of its own children (e.g. `sort | uniq`), which
    # would otherwise be orphaned and keep running after we kill just the
    # immediate process. setpgid(0,0) in the child made it its own group
    # leader; the direct pid signal is a harmless fallback if that
    # somehow didn't take.
    kill('TERM', $pid);
    kill('TERM', -$pid);
    my $deadline = time() + 1;
    while (time() < $deadline) {
        my $ret = waitpid($pid, WNOHANG);
        return 1 if $ret == $pid;
        select(undef, undef, undef, 0.05);
    }
    kill('KILL', $pid);
    kill('KILL', -$pid);
    waitpid($pid, 0);
    return 1;
}

# =============================================================================
# Shell pump — used by cmd_transform
# =============================================================================
#
# Pipe $input through `sh -c $cmd`, capturing stdout+stderr, WITHOUT the
# deadlock risk of sequential blocking I/O. IPC::Open3 pipes have a small,
# fixed OS buffer (commonly 64KB on Linux). The naive approach — write all
# of stdin, close it, then read all of stdout, then all of stderr — can
# wedge forever two different ways: (1) if the child writes enough to
# stderr to fill its pipe before we finish reading stdout, the child
# blocks writing to a full stderr pipe while we're still blocked reading
# stdout, and neither side can proceed; (2) if $input is larger than the
# stdin pipe buffer and the child doesn't drain it while producing output,
# our blocking write to stdin never returns.
#
# This pump avoids both: stdin is written in non-blocking chunks while
# stdout/stderr are drained concurrently via select(), all bounded by a
# hard wall-clock timeout. On timeout the child is killed (TERM, then KILL
# if it doesn't exit) and the caller is expected to leave the buffer
# unchanged.
#
# Returns a hashref:
#   { output => ..., stderr => ..., exit_code => ..., timed_out => 0 }
#   { timed_out => 1 }                                  (killed on timeout)
#   { spawn_error => "..." }                             (open3 itself failed)
sub _run_shell_pump {
    my ($cmd, $input, $timeout) = @_;
    $timeout //= 10;
    $input //= '';

    # A child that closes its stdin-read end early (e.g. `head -1`) would
    # otherwise deliver SIGPIPE to us on the next stdin write and kill the
    # whole editor process — ignore it locally and rely on syswrite's
    # EPIPE return instead.
    local $SIG{PIPE} = 'IGNORE';

    # Manual fork + pipes instead of IPC::Open3::open3 — open3 gives no
    # hook to run code in the child before exec, and `sh -c $cmd` can
    # spawn a whole pipeline of grandchildren (e.g. `sort | uniq`).
    # Killing just the immediate `sh` pid on timeout would leave those
    # orphaned and still running. Put the child in its own process group
    # so a timeout can kill the whole tree at once.
    my ($in_fh, $out_fh, $err_fh, $pid);
    {
        my ($child_in_r, $parent_in_w, $parent_out_r, $child_out_w, $parent_err_r, $child_err_w);
        unless (pipe($child_in_r, $parent_in_w)
             && pipe($parent_out_r, $child_out_w)
             && pipe($parent_err_r, $child_err_w)) {
            return { spawn_error => "pipe: $!" };
        }

        $pid = fork();
        if (!defined $pid) {
            return { spawn_error => "fork: $!" };
        }

        if ($pid == 0) {
            # Child
            eval { POSIX::setpgid(0, 0) };
            open(STDIN,  '<&', $child_in_r)  or POSIX::_exit(126);
            open(STDOUT, '>&', $child_out_w) or POSIX::_exit(126);
            open(STDERR, '>&', $child_err_w) or POSIX::_exit(126);
            close($_) for ($child_in_r, $parent_in_w, $parent_out_r, $child_out_w, $parent_err_r, $child_err_w);
            exec('sh', '-c', $cmd) or POSIX::_exit(127);
        }

        # Parent
        close($child_in_r);
        close($child_out_w);
        close($child_err_w);
        ($in_fh, $out_fh, $err_fh) = ($parent_in_w, $parent_out_r, $parent_err_r);
    }

    for my $fh ($in_fh, $out_fh, $err_fh) {
        my $flags = fcntl($fh, F_GETFL, 0) // 0;
        fcntl($fh, F_SETFL, $flags | O_NONBLOCK);
    }

    my $read_sel = IO::Select->new($out_fh, $err_fh);
    my $write_sel = IO::Select->new();

    my $out_buf = '';
    my $err_buf = '';
    my $in_pos = 0;
    my $in_len = length($input);
    my $in_closed = 0;
    my $out_eof = 0;
    my $err_eof = 0;

    if ($in_len) {
        $write_sel->add($in_fh);
    } else {
        # Nothing to write — close immediately so line-oriented tools that
        # wait for EOF on stdin (e.g. `sort`, `cat`) don't hang forever.
        close($in_fh);
        $in_closed = 1;
    }

    my $deadline = time() + $timeout;
    my $timed_out = 0;

    while (!($out_eof && $err_eof)) {
        if (time() >= $deadline) {
            $timed_out = 1;
            last;
        }

        my @writable = $write_sel->handles ? $write_sel->can_write(0) : ();
        for my $fh (@writable) {
            if ($in_pos < $in_len) {
                my $chunk = substr($input, $in_pos, 65536);
                my $n = syswrite($fh, $chunk);
                if (defined $n) {
                    $in_pos += $n;
                } elsif (!$!{EAGAIN} && !$!{EWOULDBLOCK}) {
                    # Broken pipe or other write error — child stopped
                    # reading stdin. Stop trying to write the rest.
                    $in_pos = $in_len;
                }
            }
            if ($in_pos >= $in_len && !$in_closed) {
                close($fh);
                $write_sel->remove($fh);
                $in_closed = 1;
            }
        }

        my @readable = $read_sel->can_read(0.1);
        for my $fh (@readable) {
            my $buf;
            my $n = sysread($fh, $buf, 65536);
            if (!defined $n) {
                next if $!{EAGAIN} || $!{EWOULDBLOCK};
                $n = 0;  # treat other read errors as EOF
            }
            if ($n == 0) {
                $read_sel->remove($fh);
                if ($fh == $out_fh) { $out_eof = 1; }
                else                { $err_eof = 1; }
                next;
            }
            if ($fh == $out_fh) { $out_buf .= $buf; }
            else                { $err_buf .= $buf; }
        }
    }

    close($in_fh) unless $in_closed;

    if ($timed_out) {
        # grace=0: skip the "wait for natural exit" phase and kill right
        # away — we already know this needs killing.
        _bounded_reap($pid, 0);
        close($out_fh);
        close($err_fh);
        return { timed_out => 1 };
    }

    close($out_fh);
    close($err_fh);
    # Bounded reap, not a bare `waitpid($pid, 0)` — reaching EOF on both
    # pipes does NOT guarantee the process has actually exited yet (e.g. a
    # daemonizing helper, or something that dup2'd its fds away and kept
    # running). An unbounded wait here would reintroduce the exact class
    # of hang this whole pump exists to prevent, just moved to the
    # "success" path instead of the timeout path.
    _bounded_reap($pid, 2);
    my $exit_code = $? >> 8;

    return {
        output    => $out_buf,
        stderr    => $err_buf,
        exit_code => $exit_code,
        timed_out => 0,
    };
}

sub cmd_transform {
    my ($self) = @_;

    my $view = $self->active_view();

    # Auto-select all if nothing is selected
    my $auto_selected;
    if (!$view->has_selection()) {
        $view->select_all();
        $auto_selected = 1;
    }

    my $last_cmd = $self->{last_transform_cmd};
    $self->open_footer_input(
        prompt => 'Shell:',
        hint   => 'sort | uniq, tac, python3 -m json.tool',
        wide   => 1,
        hint_clickable => 1,
        value  => $last_cmd,
        select_all => length($last_cmd) ? 1 : 0,
        on_submit => sub {
            my ($cmd) = @_;
            unless (length($cmd)) {
                $view->clear_selection() if $auto_selected;
                return;
            }

            $self->{last_transform_cmd} = $cmd;
            $self->_save_transform_history($cmd);

            my $doc = $self->active_doc();

            # Get input text from selection (always have one at this point)
            my ($start_off, $end_off) = $view->selection_offsets();
            my $input = $view->selected_text();

            # Ensure input ends with newline for line-oriented shell tools
            # (the document may strip trailing newlines on load)
            my $added_newline;
            if (length($input) && substr($input, -1) ne "\n") {
                $input .= "\n";
                $added_newline = 1;
            }

            # Pipe through shell command, capturing both stdout and stderr.
            # _run_shell_pump uses a select()-driven pump with a hard
            # timeout instead of sequential blocking reads — see its doc
            # comment for why the old code could deadlock or hang forever.
            # Tag the hang watchdog before/after so a diagnostic log (if
            # this somehow still wedges — e.g. a future regression) shows
            # what the main loop was doing, not just "loop".
            my $timeout = $ENV{ZEPTO_TRANSFORM_TIMEOUT} || 10;
            Zepto::HangWatchdog::heartbeat($self->{_watchdog}, "transform:$cmd");
            my $result = _run_shell_pump($cmd, $input, $timeout);
            Zepto::HangWatchdog::heartbeat($self->{_watchdog}, 'loop');

            if ($result->{spawn_error}) {
                $self->show_error_message(_user_error("Transform failed", $result->{spawn_error}));
                return;
            }

            if ($result->{timed_out}) {
                $self->show_error_message("Transform timed out");
                return;
            }

            my $output = $result->{output};
            my $stderr_text = $result->{stderr};

            # Check for command failure (non-zero exit)
            my $exit_code = $result->{exit_code};
            if ($exit_code != 0) {
                my $err = $stderr_text // '';
                chomp $err;
                $err = "Command exited with code $exit_code" unless length($err);
                $self->show_error_message($err);
                return;
            }

            if (!defined $output || !length($output)) {
                $self->show_message("Transform produced no output");
                return;
            }

            # Strip trailing newline that shell commands typically add
            chomp $output;

            # Replace the original text
            $view->clear_selection();
            $doc->replace($start_off, $end_off, $output);
            $view->invalidate_wrap_map();
        },
        on_cancel => sub {
            $view->clear_selection() if $auto_selected;
        },
    );
}

# =============================================================================
# View Commands
# =============================================================================

sub cmd_toggle_column_mode {
    my ($self) = @_;

    my $view = $self->active_view();
    return unless $view;

    if ($view->column_select()) {
        $view->exit_column_mode();
    } else {
        $view->enter_column_mode();
    }
}

sub cmd_toggle_theme {
    my ($self) = @_;
    my $current = $self->{theme}->name();
    my $new_theme = ($current eq 'dark') ? 'light' : 'dark';

    $self->{prefs}->set_theme($new_theme);
    $self->{theme} = Zepto::Theme->get_theme($new_theme);

    # Re-apply cursor color for new theme
    my $cursor_color = $self->{theme}->color('cursor_color');
    if ($cursor_color) {
        print STDOUT "\x1b]12;${cursor_color}\x1b\\";
        STDOUT->flush();
    }
}

sub cmd_toggle_nerd_font {
    my ($self) = @_;

    my $current = $self->{prefs}->nerd_font();
    my $new_state = $current ? 0 : 1;

    $self->{prefs}->set_nerd_font($new_state);
    Zepto::Chars->set_enabled($new_state);
}

sub cmd_toggle_minimap {
    my ($self) = @_;
    my $current = $self->{prefs}->show_minimap();
    $self->{prefs}->set_show_minimap($current ? 0 : 1);
}

sub cmd_toggle_autocomplete {
    my ($self) = @_;
    my $new = !$self->{prefs}->auto_complete();
    $self->{prefs}->set_auto_complete($new);
    if (!$new && $self->{_completion}) {
        $self->{_completion}->dismiss();
    }
    $self->{message} = "Auto Complete: " . ($new ? "ON" : "OFF");
}

sub cmd_toggle_auto_pairs {
    my ($self) = @_;
    my $new = !$self->{prefs}->auto_pairs();
    $self->{prefs}->set_auto_pairs($new);
    $self->{message} = "Auto Pairs: " . ($new ? "ON" : "OFF");
}

sub cmd_toggle_continue_lists {
    my ($self) = @_;
    my $new = !$self->{prefs}->continue_lists();
    $self->{prefs}->set_continue_lists($new);
    $self->{message} = "Continue Lists: " . ($new ? "ON" : "OFF");
}

sub cmd_toggle_ai {
    my ($self) = @_;
    my $ai = $self->{_ai_complete};
    return unless $ai;

    if (!$ai->{api_key} || !length($ai->{api_key})) {
        $self->show_message("No API key configured. Run 'AI Completion: Setup' first.");
        return;
    }

    $ai->{enabled} = $ai->{enabled} ? 0 : 1;
    if (!$ai->{enabled}) {
        $ai->cancel();
    }
    $self->{message} = "AI Completion: " . ($ai->{enabled} ? "ON" : "OFF");
}

sub cmd_ai_setup {
    my ($self) = @_;
    my $ai = $self->{_ai_complete};
    my $prefs = $self->{prefs};
    my $store = $self->{state_store};

    # Step 1: API URL
    $self->open_footer_input(
        prompt => 'API URL:',
        value  => $prefs->get('ai_api_url'),
        select_all => 1,
        wide   => 1,
        on_submit => sub {
            my ($url) = @_;
            return unless length($url);
            $prefs->set('ai_api_url', $url);
            $ai->{api_url} = $url;

            # Step 2: Model
            $self->open_footer_input(
                prompt => 'Model:',
                value  => $prefs->get('ai_model'),
                select_all => 1,
                wide   => 1,
                on_submit => sub {
                    my ($model) = @_;
                    return unless length($model);
                    $prefs->set('ai_model', $model);
                    $ai->{model} = $model;

                    # Step 3: API Key
                    $self->open_footer_input(
                        prompt => 'API Key:',
                        value  => $ai->{api_key} || '',
                        select_all => 1,
                        wide   => 1,
                        on_submit => sub {
                            my ($key) = @_;
                            return unless length($key);
                            $store->put('secrets', { ai_api_key => $key });
                            $ai->{api_key} = $key;
                            $ai->{enabled} = 1;
                            $self->show_message("AI Completion configured and enabled.");
                        },
                    );
                },
            );
        },
    );
}

sub cmd_toggle_word_wrap {
    my ($self) = @_;
    my $current = $self->_effective_word_wrap();
    my $view = $self->active_view();
    if ($view) {
        $view->set_word_wrap_override($current ? 0 : 1);
        # Reset horizontal scroll when enabling wrap
        $view->{scroll_col} = 0 if !$current;
        # Force WrapMap rebuild on next render
        $view->set_wrap_map(undef);
    }
}

# =============================================================================
# Tab Commands
# =============================================================================

sub cmd_prev_tab {
    my ($self) = @_;
    my $tm = $self->{tab_manager};
    return if $tm->tab_count() <= 1;

    my $idx = $tm->active_index();
    my $new_idx = ($idx - 1 + $tm->tab_count()) % $tm->tab_count();
    $self->_switch_to_tab($new_idx);
}

sub cmd_next_tab {
    my ($self) = @_;
    my $tm = $self->{tab_manager};
    return if $tm->tab_count() <= 1;

    my $idx = $tm->active_index();
    my $new_idx = ($idx + 1) % $tm->tab_count();
    $self->_switch_to_tab($new_idx);
}

sub cmd_switch_to_tab {
    my ($self, $index) = @_;
    my $tm = $self->{tab_manager};
    return if $index < 0 || $index >= $tm->tab_count();
    return if $index == $tm->active_index();

    $self->_switch_to_tab($index);
}

sub cmd_move_tab_left {
    my ($self) = @_;
    my $tm = $self->{tab_manager};
    my $idx = $tm->active_index();
    return if $idx == 0;

    $tm->move_tab($idx, $idx - 1);
}

sub cmd_move_tab_right {
    my ($self) = @_;
    my $tm = $self->{tab_manager};
    my $idx = $tm->active_index();
    return if $idx >= $tm->tab_count() - 1;

    $tm->move_tab($idx, $idx + 1);
}

sub _switch_to_tab {
    my ($self, $index) = @_;
    my $tm = $self->{tab_manager};

    # Save find state from current tab
    $self->_save_find_state_to_tab();

    # Switch to new tab
    $tm->set_active($index);

    # Restore find state from new tab
    $self->_restore_find_state_from_tab();

    # Auto-reveal active file in tree (skip when tree is focused to avoid
    # destabilizing cursor/scroll during preview navigation)
    if ($self->{file_tree} && $self->active_file_path() && !$self->{file_tree}->focused()) {
        $self->{file_tree}->set_current_file($self->active_file_path());
        $self->{file_tree}->expand_to_path($self->active_file_path());
    }
}

sub _save_find_state_to_tab {
    my ($self) = @_;
    my $tab = $self->{tab_manager}->active_tab();
    return unless $tab;

    $tab->{search_term}         = $self->{search_term};
    $tab->{search_replace}      = $self->{search_replace};
    $tab->{find_input}          = $self->{find_input};
    $tab->{find_input_cursor}   = $self->{find_input_cursor};
    $tab->{find_current}        = $self->{find_current};
    $tab->{find_regex}          = $self->{find_regex};
    $tab->{find_case}           = $self->{find_case};
    $tab->{find_replace_input}  = $self->{find_replace_input};
    $tab->{find_replace_cursor} = $self->{find_replace_cursor};
    $tab->{find_replace_active} = $self->{find_replace_active};
    $tab->{find_focus}          = $self->{find_focus};
    $tab->{find_replace_all}    = $self->{find_replace_all};
    $tab->{find_matches}        = $self->{find_matches};
    $tab->{find_replaced}       = $self->{find_replaced};
    $tab->{find_replace_preview} = $self->{find_replace_preview};
}

sub _restore_find_state_from_tab {
    my ($self) = @_;
    my $tab = $self->{tab_manager}->active_tab();
    return unless $tab;

    $self->{search_term}         = $tab->{search_term} // '';
    $self->{search_replace}      = $tab->{search_replace} // '';
    $self->{find_input}          = $tab->{find_input} // '';
    $self->{find_input_cursor}   = $tab->{find_input_cursor} // 0;
    $self->{find_current}        = $tab->{find_current} // 0;
    $self->{find_regex}          = $tab->{find_regex} // 1;
    $self->{find_case}           = $tab->{find_case} // 0;
    $self->{find_replace_input}  = $tab->{find_replace_input} // '';
    $self->{find_replace_cursor} = $tab->{find_replace_cursor} // 0;
    $self->{find_replace_active} = $tab->{find_replace_active} // 0;
    $self->{find_focus}          = $tab->{find_focus} // 'find';
    $self->{find_replace_all}    = $tab->{find_replace_all} // 1;
    $self->{find_matches}        = $tab->{find_matches} // [];
    $self->{find_replaced}       = $tab->{find_replaced} // [];
    $self->{find_replace_preview} = $tab->{find_replace_preview};
}

# =============================================================================
# Diagnostics Commands
# =============================================================================

sub cmd_show_perf_log {
    my ($self) = @_;

    my $log = $self->{_perf_log};
    my $content;

    if (!$log || !@$log) {
        $content = "No frames recorded yet.\n";
    } else {
        my @lines;
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
        my $generated = sprintf('%04d-%02d-%02d %02d:%02d:%02d',
            $year + 1900, $mon + 1, $mday, $hour, $min, $sec);

        push @lines, "Zepto Performance Report";
        push @lines, "========================";
        push @lines, "Generated: $generated";
        push @lines, sprintf("Showing: %d slowest frames", scalar @$log);
        push @lines, "";

        # Header
        push @lines, sprintf("%-4s %-9s %-9s %-9s %-10s %-8s %-24s %s",
            '#', 'Time', 'Event', 'Render', 'State', 'Trigger', 'Subsystems', 'File');

        # Entries
        my $i = 1;
        for my $entry (@$log) {
            my $file_display = $entry->{file};
            $file_display .= " ($entry->{lines} lines)" if $entry->{lines};

            push @lines, sprintf("%-4d %-9s %-9s %-9s %-10s %-8s %-24s %s",
                $i,
                sprintf('%.1fms', $entry->{total_ms}),
                sprintf('%.1fms', $entry->{event_ms}),
                sprintf('%.1fms', $entry->{render_ms}),
                $entry->{state},
                $entry->{event_type},
                $entry->{subsystems},
                $file_display,
            );
            $i++;
        }

        push @lines, "";
        push @lines, "Features active: $log->[0]{features}" if @$log;

        $content = join("\n", @lines) . "\n";
    }

    # Open as a new untitled tab — reuse _open_content_tab helper
    $self->_open_content_tab($content, 'Performance Log');
}

# =============================================================================
# Documentation Commands
# =============================================================================

use Zepto::HelpDocs;

sub _open_help_doc {
    my ($self, $doc_id) = @_;
    my $label = Zepto::HelpDocs->doc_label($doc_id);
    my $content = Zepto::HelpDocs->doc_content($doc_id);
    $self->_open_content_tab($content, $label, syntax => 'markdown');
}

sub cmd_doc_about     { $_[0]->_open_help_doc('about') }
sub cmd_doc_tutorial  { $_[0]->_open_help_doc('tutorial') }
sub cmd_doc_changelog { $_[0]->_open_help_doc('changelog') }
sub cmd_doc_license   { $_[0]->_open_help_doc('license') }

1;
