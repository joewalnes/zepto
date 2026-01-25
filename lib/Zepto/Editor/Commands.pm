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

    my $doc = $self->{document};

    unless ($doc->path()) {
        # Need to get filename
        $self->open_dialog(
            title => 'Save As',
            prompt => 'Filename:',
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

sub cmd_save_and_quit {
    my ($self) = @_;
    $self->cmd_save();
    # Only quit if save succeeded
    unless ($self->{document}->is_dirty()) {
        $self->{state} = STATE_QUIT;
    }
}

sub cmd_quit {
    my ($self) = @_;

    if ($self->{document}->is_dirty()) {
        if ($self->{quit_pending}) {
            # Second Ctrl+Q - force quit
            $self->{state} = STATE_QUIT;
        }
        else {
            $self->{quit_pending} = 1;
            $self->show_message("Unsaved changes! Press Ctrl+Q again to quit.");
        }
    }
    else {
        $self->{state} = STATE_QUIT;
    }
}

# =============================================================================
# Edit Commands
# =============================================================================

sub cmd_undo {
    my ($self) = @_;
    if ($self->{document}->undo()) {
        $self->show_message("Undo");
    }
    else {
        $self->show_message("Nothing to undo");
    }
}

sub cmd_redo {
    my ($self) = @_;
    if ($self->{document}->redo()) {
        $self->show_message("Redo");
    }
    else {
        $self->show_message("Nothing to redo");
    }
}

sub cmd_cut {
    my ($self) = @_;

    my $view = $self->{view};

    if ($view->has_selection()) {
        $self->{clipboard} = $view->selected_text();
        $self->delete_selection();
        $self->show_message("Cut");
    }
}

sub cmd_copy {
    my ($self) = @_;

    my $view = $self->{view};

    if ($view->has_selection()) {
        $self->{clipboard} = $view->selected_text();
        $self->show_message("Copied");
    }
}

sub cmd_paste {
    my ($self) = @_;

    return unless length $self->{clipboard};

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

    $doc->insert($offset, $self->{clipboard});

    # Move cursor to end of pasted text
    my $end_offset = $offset + length($self->{clipboard});
    my ($line, $col) = $doc->offset_to_line_col($end_offset);
    $view->set_cursor($line, $col);

    $self->show_message("Pasted");
}

sub cmd_select_all {
    my ($self) = @_;
    $self->{view}->select_all();
}

# =============================================================================
# Search Commands
# =============================================================================

sub cmd_find {
    my ($self) = @_;

    $self->open_dialog(
        title => 'Find',
        prompt => 'Search for:',
        value => $self->{search_term},
        on_submit => sub {
            my ($term) = @_;
            if ($term) {
                $self->{search_term} = $term;
                $self->do_find_next();
            }
        },
    );
}

sub cmd_find_next {
    my ($self) = @_;

    if ($self->{search_term}) {
        $self->do_find_next();
    }
    else {
        $self->cmd_find();
    }
}

sub cmd_find_prev {
    my ($self) = @_;

    if ($self->{search_term}) {
        $self->do_find_prev();
    }
    else {
        $self->cmd_find();
    }
}

sub do_find_next {
    my ($self) = @_;

    my $doc = $self->{document};
    my $view = $self->{view};
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

    my $doc = $self->{document};
    my $view = $self->{view};
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

sub cmd_replace {
    my ($self) = @_;

    $self->open_dialog(
        title => 'Replace',
        prompt => 'Find:',
        value => $self->{search_term},
        on_submit => sub {
            my ($find) = @_;
            if ($find) {
                $self->{search_term} = $find;
                $self->open_dialog(
                    title => 'Replace',
                    prompt => 'Replace with:',
                    value => $self->{search_replace},
                    on_submit => sub {
                        my ($replace) = @_;
                        $self->{search_replace} = $replace // '';
                        $self->do_replace_all();
                    },
                );
            }
        },
    );
}

sub do_replace_all {
    my ($self) = @_;

    my $doc = $self->{document};
    my $find = $self->{search_term};
    my $replace = $self->{search_replace};

    return unless $find;

    my $text = $doc->text();
    my $count = 0;
    my $offset = 0;

    while ((my $pos = index($text, $find, $offset)) >= 0) {
        $doc->delete($pos, length($find));
        $doc->insert($pos, $replace);
        $text = $doc->text();  # Refresh
        $offset = $pos + length($replace);
        $count++;
    }

    $self->show_message("Replaced $count occurrences");
}

sub cmd_goto_line {
    my ($self) = @_;

    $self->open_dialog(
        title => 'Go to Line',
        prompt => 'Line number:',
        on_submit => sub {
            my ($num) = @_;
            if ($num && $num =~ /^\d+$/) {
                my $line = $num - 1;  # Convert to 0-indexed
                $line = 0 if $line < 0;
                my $max = $self->{document}->line_count() - 1;
                $line = $max if $line > $max;
                $self->{view}->set_cursor($line, 0);
            }
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

1;
