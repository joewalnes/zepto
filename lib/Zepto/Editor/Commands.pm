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

use Zepto::Theme;

# Note: STATE_QUIT constant is defined in Zepto::Editor and accessible here

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
                        $self->show_message("Error: $@");
                    }
                    else {
                        $self->show_message("Saved: $filename");
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
        $self->show_message("Error: $@");
    }
    else {
        $self->show_message("Saved: " . $doc->filename());
    }
}

sub cmd_close_tab {
    my ($self) = @_;

    my $doc = $self->active_doc();

    if ($doc->is_dirty()) {
        my $name = $self->active_tab()->{untitled_name}
                || $doc->filename()
                || '[untitled]';
        $self->open_prompt(
            text => "Save changes to $name?",
            options => [
                { key => 'y', label => 'Yes' },
                { key => 'n', label => 'No' },
                { key => 'c', label => 'Cancel' },
            ],
            on_select => sub {
                my ($choice) = @_;
                if ($choice eq 'y') {
                    $self->cmd_save();
                    # Close after save succeeds
                    unless ($self->active_doc()->is_dirty()) {
                        $self->_do_close_tab($self->{tab_manager}->active_index());
                    }
                }
                elsif ($choice eq 'n') {
                    $self->_do_close_tab($self->{tab_manager}->active_index());
                }
                # 'c' = cancel, do nothing
            },
        );
    }
    else {
        $self->_do_close_tab($self->{tab_manager}->active_index());
    }
}

sub _do_close_tab {
    my ($self, $index) = @_;
    my $tm = $self->{tab_manager};

    # If this is the last tab, quit
    if ($tm->tab_count() <= 1) {
        $self->{state} = STATE_QUIT;
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
        $self->{state} = STATE_QUIT;
        return;
    }

    # Walk through dirty tabs one at a time
    $self->_prompt_close_dirty_tabs(\@dirty, sub {
        $self->{state} = STATE_QUIT;
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

    $self->open_prompt(
        text => "Save changes to $name?",
        options => [
            { key => 'y', label => 'Yes' },
            { key => 'n', label => 'No' },
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
    $self->_open_file_picker();
}

sub _open_file_picker {
    my ($self) = @_;

    $self->open_file_picker(
        base_dir => '.',
        on_select => sub {
            my ($file) = @_;
            $self->_load_file($file);
        },
        on_cancel => sub {
            # Just close picker, do nothing
        },
    );
}

sub _load_file {
    my ($self, $path) = @_;

    # Check if file is already open in another tab
    my $existing = $self->{tab_manager}->find_tab_by_path($path);
    if (defined $existing) {
        $self->_switch_to_tab($existing);
        return;
    }

    eval {
        my ($doc, $view, $find_engine, $highlighter) = $self->_create_document_state($path);
        $self->{tab_manager}->add_tab(
            document    => $doc,
            view        => $view,
            find_engine => $find_engine,
            highlighter => $highlighter,
            file_path   => $path,
        );
    };
    if ($@) {
        $self->show_message("Error opening file: $@");
    }
}

# =============================================================================
# Edit Commands
# =============================================================================

sub cmd_undo {
    my ($self) = @_;
    if ($self->active_doc()->undo()) {
        $self->show_message("Undo");
    }
    else {
        $self->show_message("Nothing to undo");
    }
}

sub cmd_redo {
    my ($self) = @_;
    if ($self->active_doc()->redo()) {
        $self->show_message("Redo");
    }
    else {
        $self->show_message("Nothing to redo");
    }
}

sub cmd_cut {
    my ($self) = @_;

    my $view = $self->active_view();

    # If no selection, select current line first
    $view->select_line() unless $view->has_selection();

    if ($view->has_selection()) {
        $self->{clipboard} = $view->selected_text();
        $self->{terminal}->copy_to_clipboard($self->{clipboard});
        $self->delete_selection();
        $self->show_message("Cut");
    }
}

sub cmd_copy {
    my ($self) = @_;

    my $view = $self->active_view();
    my $doc = $self->active_doc();

    # If no selection, copy current line (including newline if not last line)
    unless ($view->has_selection()) {
        my $line = $view->cursor_line();
        my $content = $doc->get_line_content($line);

        # Add newline if not the last line
        if ($line < $doc->line_count() - 1) {
            $content .= "\n";
        }

        $self->{clipboard} = $content;
        $self->{terminal}->copy_to_clipboard($self->{clipboard});

        # Select the line visually (cursor stays at end of line)
        my $line_len = $doc->line_length($line);
        $view->set_cursor($line, 0, 0);        # Start of line, no extend
        $view->set_cursor($line, $line_len, 1); # End of line, extend selection

        $self->show_message("Copied line");
        return;
    }

    $self->{clipboard} = $view->selected_text();
    $self->{terminal}->copy_to_clipboard($self->{clipboard});
    $self->show_message("Copied");
}

sub cmd_paste {
    my ($self) = @_;

    # Try system clipboard first, fall back to internal clipboard
    my $text = $self->{terminal}->paste_from_clipboard();
    if (length $text) {
        $self->{clipboard} = $text;  # Sync internal clipboard
    }

    return unless length $self->{clipboard};

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

    $doc->insert($offset, $self->{clipboard});

    # Move cursor to end of pasted text
    my $end_offset = $offset + length($self->{clipboard});
    my ($line, $col) = $doc->offset_to_line_col($end_offset);
    $view->set_cursor($line, $col);

    $self->show_message("Pasted");
}

sub cmd_select_all {
    my ($self) = @_;
    $self->active_view()->select_all();
}

# =============================================================================
# Search Commands
# =============================================================================

sub cmd_find {
    my ($self) = @_;
    $self->enter_find_mode();
}

sub cmd_find_next {
    my ($self) = @_;

    if ($self->{search_term}) {
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

sub cmd_goto_line {
    my ($self) = @_;

    my $current_line = $self->active_view()->cursor_line();

    $self->open_footer_input(
        prompt => 'Go to:',
        hint => 'line or line:col or :col',
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
                return;  # Invalid input
            }

            # Clamp line to valid range
            my $max_line = $self->active_doc()->line_count() - 1;
            $line = 0 if $line < 0;
            $line = $max_line if $line > $max_line;

            # Clamp column to line length
            $col = 0 if $col < 0;
            my $max_col = $self->active_doc()->line_length($line);
            $col = $max_col if $col > $max_col;

            $self->active_view()->set_cursor($line, $col);
        },
    );
}

# =============================================================================
# View Commands
# =============================================================================

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

sub cmd_toggle_powerline {
    my ($self) = @_;

    my $current = $self->{prefs}->powerline();
    my $new_state = $current ? 0 : 1;

    $self->{prefs}->set_powerline($new_state);
    Zepto::Chars->set_enabled($new_state);
}

sub cmd_toggle_minimap {
    my ($self) = @_;
    my $current = $self->{prefs}->show_minimap();
    $self->{prefs}->set_show_minimap($current ? 0 : 1);
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

1;
