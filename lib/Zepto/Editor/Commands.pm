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
use IPC::Open3;
use IO::Select;

use Symbol 'gensym';

use Zepto::Theme;

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
                $self->_finish_save_as($doc, $filename) if $filename;
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

# Save As: always prompts for a path (unlike cmd_save, which only
# prompts when the document has no path yet). Prefills the current
# path so re-saving under a tweaked name is a quick edit. Confirms
# before overwriting an existing file that isn't the document's own
# current path.
sub cmd_save_as {
    my ($self) = @_;

    my $doc = $self->active_doc();
    my $current_path = $doc->path();

    $self->open_footer_input(
        prompt => 'Save As:',
        value  => defined $current_path ? $current_path : '',
        select_all => defined $current_path ? 1 : 0,
        on_submit => sub {
            my ($filename) = @_;
            return unless defined $filename && length $filename;

            # Confirm before silently overwriting a different existing file.
            # Saving to the document's own current path is not an "overwrite"
            # in the user-surprise sense, so it's exempt from the prompt.
            my $is_different_file = !defined($current_path) || $filename ne $current_path;
            if ($is_different_file && -e $filename) {
                $self->open_prompt(
                    text    => "'$filename' already exists. Overwrite?",
                    options => [
                        { key => 'y', label => 'Yes' },
                        { key => 'n', label => 'No' },
                    ],
                    on_select => sub {
                        my ($choice) = @_;
                        $self->_finish_save_as($doc, $filename) if $choice eq 'y';
                    },
                );
                return;
            }

            $self->_finish_save_as($doc, $filename);
        },
        on_cancel => sub {
            $self->show_message("Save As cancelled");
        },
    );
}

# Shared tail of the Save As flow: write the file at $filename, then
# update the tab path/title and re-detect syntax highlighting for the
# new extension. Used by both cmd_save (untitled-document path) and
# cmd_save_as (explicit command).
sub _finish_save_as {
    my ($self, $doc, $filename) = @_;

    $doc->set_path($filename);
    eval { $doc->save(); };
    if ($@) {
        $self->show_error_message(_user_error("Save failed", $@));
        return;
    }

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
        $self->_save_session();
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
        $self->_save_session();
        $self->{state} = 'quit';
        return;
    }

    # Walk through dirty tabs one at a time
    $self->_prompt_close_dirty_tabs(\@dirty, sub {
        $self->_save_session();
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
    $self->{palette}->open_files();
}

sub cmd_recent_files {
    my ($self) = @_;
    $self->{palette}->open_recent_files();
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
        # Undo can shrink the document underneath the view (e.g. undoing a
        # multi-line paste), leaving the cursor past the last line. Re-clamp
        # before anything else reads it -- see View::clamp_to_document.
        $self->active_view()->clamp_to_document();
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
        # Redo can also shrink the document (redoing a delete), so it needs
        # the same re-clamp as undo.
        $self->active_view()->clamp_to_document();
        $self->show_message("Redo");
        $self->_retrigger_completion_if_word();
    }
    else {
        $self->show_message("Nothing to redo");
    }
}

sub cmd_cut {
    my ($self) = @_;

    my $view = $self->active_view();

    # Column selection: copy rectangle then delete
    if ($view->column_select() && $view->has_selection()) {
        my $lines = $view->column_selected_text();
        $self->{clipboard} = join("\n", @$lines);
        $self->{clipboard_columnar} = 1;
        my $copied = $self->{terminal}->copy_to_clipboard($self->{clipboard});
        $self->delete_selection();
        # The internal clipboard/cut always succeeds regardless of the
        # system clipboard's fate; only the message differs. copy_to_clipboard
        # returns undef specifically when the platform clipboard command
        # hung past its timeout (see Terminal.pm::copy_to_clipboard) --
        # distinct from '' (skipped, e.g. no system clipboard) or 1 (ok).
        if (!defined $copied) {
            $self->show_error_message(_user_error("Cut", "system clipboard write timed out"));
        } else {
            $self->show_message("Cut " . scalar(@$lines) . " lines (column)");
        }
        return;
    }

    # If no selection, select current line first
    $view->select_line() unless $view->has_selection();

    if ($view->has_selection()) {
        $self->{clipboard} = $view->selected_text();
        $self->{clipboard_columnar} = 0;
        my $copied = $self->{terminal}->copy_to_clipboard($self->{clipboard});
        $self->delete_selection();
        if (!defined $copied) {
            $self->show_error_message(_user_error("Cut", "system clipboard write timed out"));
        } else {
            $self->show_message("Cut");
        }
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
        my $copied = $self->{terminal}->copy_to_clipboard($self->{clipboard});
        # copy_to_clipboard returns undef specifically when the platform
        # clipboard command hung past its timeout (see
        # Terminal.pm::copy_to_clipboard) -- distinct from '' (skipped,
        # e.g. no system clipboard) or 1 (ok). The internal clipboard
        # copy always succeeds regardless; only the message differs.
        if (!defined $copied) {
            $self->show_error_message(_user_error("Copy", "system clipboard write timed out"));
        } else {
            $self->show_message("Copied " . scalar(@$lines) . " lines (column)");
        }
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
        my $copied = $self->{terminal}->copy_to_clipboard($self->{clipboard});

        # Select the line visually (cursor stays at end of line)
        my $line_len = $doc->line_length($line);
        $view->set_cursor($line, 0, 0);        # Start of line, no extend
        $view->set_cursor($line, $line_len, 1); # End of line, extend selection

        if (!defined $copied) {
            $self->show_error_message(_user_error("Copy", "system clipboard write timed out"));
        } else {
            $self->show_message("Copied line");
        }
        return;
    }

    $self->{clipboard} = $view->selected_text();
    $self->{clipboard_columnar} = 0;
    my $copied = $self->{terminal}->copy_to_clipboard($self->{clipboard});
    if (!defined $copied) {
        $self->show_error_message(_user_error("Copy", "system clipboard write timed out"));
    } else {
        $self->show_message("Copied");
    }
}

sub cmd_paste {
    my ($self) = @_;

    # Try system clipboard first, fall back to internal clipboard.
    # paste_from_clipboard() returns undef specifically when the platform
    # clipboard command hung past its timeout (bugs.md P1 "Clipboard
    # paste has no timeout") -- distinct from '' (no content), so we can
    # surface a real error instead of silently falling back.
    my $text = $self->{terminal}->paste_from_clipboard();
    if (!defined $text) {
        $self->show_error_message(_user_error("Paste failed", "clipboard read timed out"));
    } elsif (length $text) {
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
        last if $target_line >= $doc->line_count();

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

# bugs.md P2 "No on-screen indicator for Replace-One vs. Replace-All
# mode, and no palette command to switch between them" -- opens Find and
# Replace if it isn't already open, then toggles the mode and confirms
# via the status message (the find bar's "Rep All:"/"Rep One:" label
# also updates).
sub cmd_toggle_replace_all_mode {
    my ($self) = @_;
    $self->enter_find_mode(replace => 1) unless $self->{find_replace_active};
    $self->_toggle_replace_all_mode();
    $self->show_message($self->{find_replace_all} ? 'Replace All mode' : 'Replace One mode');
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

sub cmd_find_in_files {
    my ($self) = @_;
    $self->{palette}->open_find_in_files();
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
            #
            # IMPORTANT: stdout and stderr must be read concurrently, not
            # sequentially. If the child writes enough to stderr (>~64KB,
            # the typical OS pipe buffer size) while also writing to
            # stdout, reading stdout to EOF first blocks the parent
            # forever while the child blocks writing to a full stderr
            # pipe nobody is reading yet -- the classic IPC::Open3
            # synchronous-read deadlock (perldoc IPC::Open3 warns about
            # this explicitly). Since raw mode disables ISIG, the user
            # can't even Ctrl-C out. Use IO::Select to drain whichever
            # handle has data ready, in any order. See bugs.md P1
            # "cmd_transform can deadlock the whole editor" / QA-REG-187.
            my ($output, $stderr_text) = ('', '');
            eval {
                my $err_fh = gensym;
                my $pid = open3(my $in_fh, my $out_fh, $err_fh, 'sh', '-c', $cmd);
                print $in_fh $input;
                close $in_fh;

                binmode($out_fh, ':raw');
                binmode($err_fh, ':raw');

                my $sel = IO::Select->new($out_fh, $err_fh);
                while ($sel->count) {
                    for my $fh ($sel->can_read) {
                        my $buf;
                        my $n = sysread($fh, $buf, 65536);
                        if (!defined $n || $n == 0) {
                            # EOF or read error -- stop watching this handle
                            $sel->remove($fh);
                            close $fh;
                            next;
                        }
                        if (fileno($fh) == fileno($out_fh)) {
                            $output .= $buf;
                        } else {
                            $stderr_text .= $buf;
                        }
                    }
                }
                waitpid($pid, 0);
            };

            if ($@) {
                $self->show_error_message(_user_error("Transform failed", $@));
                return;
            }

            # Check for command failure (non-zero exit)
            my $exit_code = $? >> 8;
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
# Built-in Text Transforms (pure Perl, no shell exec — see cmd_transform
# above for the ⌥T shell-pipe version, which is unchanged). Palette
# section: TRANSFORM.
# =============================================================================

# Shared engine: apply $fn->($text) to the current selection, or the whole
# document if nothing is selected (same auto-select-all scoping cmd_transform
# uses). No-op (no undo entry, no dirty flag) if the transform doesn't
# actually change the text.
sub _apply_text_transform {
    my ($self, $fn) = @_;

    my $view = $self->active_view();
    my $doc  = $self->active_doc();

    my $auto_selected;
    if (!$view->has_selection()) {
        $view->select_all();
        $auto_selected = 1;
    }

    my ($start_off, $end_off) = $view->selection_offsets();
    my $input = $view->selected_text();
    my $output = $fn->($input);

    if (!defined $output || $output eq $input) {
        $view->clear_selection() if $auto_selected;
        return;
    }

    $view->clear_selection();
    $doc->replace($start_off, $end_off, $output);
    $view->invalidate_wrap_map();
}

# Line-oriented variant of _apply_text_transform: splits the selected text
# into lines, calls $fn->(@lines) (which returns the transformed list of
# lines), and rejoins — preserving whether the original text ended with a
# trailing newline.
sub _apply_line_transform {
    my ($self, $fn) = @_;

    $self->_apply_text_transform(sub {
        my ($text) = @_;
        return $text unless length($text);

        my @lines = split /\n/, $text, -1;
        my $trailing_nl = (@lines && $lines[-1] eq '') ? 1 : 0;
        pop @lines if $trailing_nl;

        @lines = $fn->(@lines);

        my $result = join("\n", @lines);
        $result .= "\n" if $trailing_nl;
        return $result;
    });
}

sub cmd_transform_uppercase {
    my ($self) = @_;
    $self->_apply_text_transform(sub { uc $_[0] });
}

sub cmd_transform_lowercase {
    my ($self) = @_;
    $self->_apply_text_transform(sub { lc $_[0] });
}

sub cmd_transform_sort_lines {
    my ($self) = @_;
    $self->_apply_line_transform(sub { sort @_ });
}

sub cmd_transform_reverse_lines {
    my ($self) = @_;
    $self->_apply_line_transform(sub { reverse @_ });
}

# Removes duplicate lines, keeping the first occurrence and preserving
# original order (unlike shell `sort -u`, which reorders).
sub cmd_transform_unique_lines {
    my ($self) = @_;
    $self->_apply_line_transform(sub {
        my %seen;
        return grep { !$seen{$_}++ } @_;
    });
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

# Set the theme preference to an explicit value ('auto'|'dark'|'light')
# and immediately resolve/apply the concrete theme it maps to. Shared by
# cmd_toggle_theme and the palette's explicit Theme: Auto/Dark/Light
# commands.
sub _apply_theme_pref {
    my ($self, $pref_value) = @_;

    $self->{prefs}->set_theme($pref_value);
    $self->{_theme_effective} = $self->_resolve_theme_name($pref_value);
    $self->{theme} = Zepto::Theme->get_theme($self->{_theme_effective});

    # Re-apply cursor color for new theme
    my $cursor_color = $self->{theme}->color('cursor_color');
    $self->{terminal}->set_cursor_color($cursor_color) if $cursor_color;
}

# ⌃T: toggle between the explicit opposite of whatever theme is currently
# effective — including while in 'auto' mode. This is a deliberate design
# choice: ⌃T always means "I want the OTHER look, right now", and setting
# an explicit dark/light preference naturally LEAVES auto mode (the pref
# is no longer 'auto'). To re-enable auto mode, use the "Theme: Auto"
# palette command — ⌃T itself never re-enters auto.
sub cmd_toggle_theme {
    my ($self) = @_;
    my $current = $self->{theme}->name();  # effective theme, even under auto
    my $new_theme = ($current eq 'dark') ? 'light' : 'dark';
    $self->_apply_theme_pref($new_theme);
}

# Palette commands: jump directly to a specific theme mode.
sub cmd_set_theme_auto  { $_[0]->_apply_theme_pref('auto'); }
sub cmd_set_theme_dark  { $_[0]->_apply_theme_pref('dark'); }
sub cmd_set_theme_light { $_[0]->_apply_theme_pref('light'); }

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

# Flip a boolean preference and set the standard "Label: ON/OFF" status
# message. Shared by the toggle-preference commands below, which all
# previously copy-pasted the same get/flip/set/message-format shape.
# Returns the new (post-flip) value so callers needing an additional side
# effect keyed off it (e.g. cmd_toggle_mouse enabling/disabling the
# terminal) can run it after the preference is persisted.
sub _toggle_pref {
    my ($self, $getter, $setter, $label, %opts) = @_;
    my $on_label  = $opts{on_label}  // 'ON';
    my $off_label = $opts{off_label} // 'OFF';

    my $new = !$getter->();
    $setter->($new);
    $self->show_message("$label: " . ($new ? $on_label : $off_label));
    return $new;
}

sub cmd_toggle_autocomplete {
    my ($self) = @_;
    my $new = $self->_toggle_pref(
        sub { $self->{prefs}->auto_complete() },
        sub { $self->{prefs}->set_auto_complete($_[0]) },
        'Auto Complete',
    );
    if (!$new && $self->{_completion}) {
        $self->{_completion}->dismiss();
    }
}

sub cmd_toggle_auto_pairs {
    my ($self) = @_;
    $self->_toggle_pref(
        sub { $self->{prefs}->auto_pairs() },
        sub { $self->{prefs}->set_auto_pairs($_[0]) },
        'Auto Pairs',
    );
}

sub cmd_toggle_restore_session {
    my ($self) = @_;
    $self->_toggle_pref(
        sub { $self->{prefs}->restore_session() },
        sub { $self->{prefs}->set_restore_session($_[0]) },
        'Restore Session on Startup',
    );
}

sub cmd_toggle_mouse {
    my ($self) = @_;
    my $new = $self->_toggle_pref(
        sub { $self->{prefs}->mouse_enabled() },
        sub { $self->{prefs}->set_mouse_enabled($_[0]) },
        'Mouse',
    );

    my $term = $self->{terminal};
    if ($term) {
        $new ? $term->enable_mouse() : $term->disable_mouse();
    }
}

sub cmd_toggle_search_wrap {
    my ($self) = @_;
    $self->_toggle_pref(
        sub { $self->{prefs}->search_wrap() },
        sub { $self->{prefs}->set_search_wrap($_[0]) },
        'Search Wrap Around',
    );
}

sub cmd_toggle_markdown_tables {
    my ($self) = @_;
    $self->_toggle_pref(
        sub { $self->{prefs}->render_markdown_tables() },
        sub { $self->{prefs}->set_render_markdown_tables($_[0]) },
        'Markdown Table Rendering',
    );
}

sub cmd_toggle_soft_tabs {
    my ($self) = @_;
    $self->_toggle_pref(
        sub { $self->{prefs}->soft_tabs() },
        sub { $self->{prefs}->set_soft_tabs($_[0]) },
        'Soft Tabs',
        on_label  => 'ON (spaces)',
        off_label => 'OFF (tabs)',
    );
}

sub cmd_toggle_auto_indent {
    my ($self) = @_;
    $self->_toggle_pref(
        sub { $self->{prefs}->auto_indent() },
        sub { $self->{prefs}->set_auto_indent($_[0]) },
        'Auto Indent',
    );
}

# Valid range for the "Tab Width" preference (cmd_set_tab_width below).
use constant {
    TAB_WIDTH_MIN => 1,
    TAB_WIDTH_MAX => 16,
};

sub cmd_set_tab_width {
    my ($self) = @_;
    my $prefs = $self->{prefs};

    $self->open_footer_input(
        prompt => 'Tab Width:',
        value  => $prefs->tab_width(),
        select_all => 1,
        hint   => TAB_WIDTH_MIN . '-' . TAB_WIDTH_MAX,
        id     => 'set_tab_width',
        on_submit => sub {
            my ($input) = @_;
            return unless defined $input && $input =~ /\S/;

            unless ($input =~ /^\d+$/ && $input >= TAB_WIDTH_MIN && $input <= TAB_WIDTH_MAX) {
                $self->show_error_message(
                    "Invalid tab width. Use a number " . TAB_WIDTH_MIN . '-' . TAB_WIDTH_MAX . "."
                );
                return;
            }

            $prefs->set_tab_width($input + 0);
            $self->show_message("Tab Width: $input");
        },
    );
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
    $self->show_message("AI Completion: " . ($ai->{enabled} ? "ON" : "OFF"));
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

            # Reject non-https URLs: the AI completion request sends the
            # user's API key as an Authorization header on every request
            # (AIComplete.pm), so a non-https endpoint (mistyped/pasted
            # "http://...") would silently transmit that key in plaintext.
            # See bugs.md "AI API URL has no scheme enforcement".
            unless ($url =~ m{^https://}i) {
                $self->show_error_message(
                    "API URL must start with https:// (got: $url). "
                    . "The API key is sent as a request header, so a "
                    . "non-https URL would transmit it in plaintext."
                );
                return;
            }

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
