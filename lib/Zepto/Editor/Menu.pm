package Zepto::Editor::Menu;
# =============================================================================
# Editor Menu Handling - Dropdown menus and navigation
# =============================================================================
#
# This module defines menu-related methods for the Zepto::Editor class.
# Handles opening/closing menus, navigation, and executing menu items.
# =============================================================================

use strict;
use warnings;

# Define methods in Zepto::Editor's namespace
package Zepto::Editor;

use Zepto::Renderer;
use Zepto::InputParser;

# Note: STATE_MENU, STATE_EDITING constants are defined in Zepto::Editor and accessible here

# =============================================================================
# Menu State
# =============================================================================

sub open_menu {
    my ($self, $key) = @_;
    $self->{state} = STATE_MENU;
    $self->{menu_open} = $key;
    $self->{menu_selected} = 0;
}

sub close_menu {
    my ($self) = @_;
    $self->{state} = STATE_EDITING;
    $self->{menu_open} = undef;
    $self->{menu_selected} = 0;
}

# =============================================================================
# Menu Click Handling
# =============================================================================

sub handle_menu_click {
    my ($self, $x) = @_;

    # Check for clicks on Save/Quit buttons (right side of menu bar)
    my @buttons = Zepto::Renderer::get_menu_bar_buttons();
    for my $btn (@buttons) {
        if ($x >= $btn->{x_start} && $x <= $btn->{x_end}) {
            my $action = $btn->{action};
            if ($action eq 'save') {
                $self->cmd_save();
            }
            elsif ($action eq 'quit') {
                $self->cmd_quit();
            }
            return;
        }
    }

    # Use dynamically calculated positions from Renderer for menus
    my $positions = Zepto::Renderer::get_menu_positions();

    for my $key (keys %$positions) {
        my $pos = $positions->{$key};
        if ($x >= $pos->{start} && $x <= $pos->{end}) {
            if ($self->{menu_open} eq $key) {
                $self->close_menu();
            }
            else {
                $self->open_menu($key);
            }
            return;
        }
    }

    # Click outside menus
    $self->close_menu() if $self->{menu_open};
}

# =============================================================================
# Menu Event Handling
# =============================================================================

sub handle_menu_event {
    my ($self, $event) = @_;

    my $type = $event->{type};

    if ($type eq 'key') {
        my $key = $event->{key};

        if ($key eq 'up') {
            $self->menu_move(-1);
        }
        elsif ($key eq 'down') {
            $self->menu_move(1);
        }
        elsif ($key eq 'enter') {
            $self->execute_menu_item();
        }
        elsif ($key eq 'escape') {
            $self->close_menu();
        }
        elsif ($key eq 'left') {
            $self->prev_menu();
        }
        elsif ($key eq 'right') {
            $self->next_menu();
        }
    }
    elsif ($type eq 'char') {
        if (Zepto::InputParser::has_modifier($event, 'alt')) {
            $self->handle_alt_char($event->{char});
        }
    }
    elsif ($type eq 'mouse') {
        if ($event->{action} eq 'press') {
            if ($event->{y} == 1) {
                # Click on menu bar
                $self->handle_menu_click($event->{x});
            }
            else {
                # Check if click is within dropdown area
                my @items = @{$self->_menu_items()};
                my $positions = Zepto::Renderer::get_menu_positions();
                my $menu_x = $positions->{$self->{menu_open}}{x} // 1;
                my $menu_width = Zepto::Renderer::MENU_DROPDOWN_WIDTH;

                my $item_idx = $event->{y} - 2;  # Row 2 = item 0
                my $x = $event->{x};

                # Check if click is within dropdown bounds
                if ($item_idx >= 0 && $item_idx < @items &&
                    $x >= $menu_x && $x < $menu_x + $menu_width) {
                    # Skip separators
                    if ($items[$item_idx] ne '-') {
                        $self->{menu_selected} = $item_idx;
                        $self->execute_menu_item();
                    }
                }
                else {
                    $self->close_menu();
                }
            }
        }
    }
}

# =============================================================================
# Menu Navigation
# =============================================================================

sub prev_menu {
    my ($self) = @_;
    my @menus = qw(f e s v);
    my $idx = 0;
    for my $i (0..$#menus) {
        $idx = $i if $menus[$i] eq $self->{menu_open};
    }
    $idx = ($idx - 1 + @menus) % @menus;
    $self->open_menu($menus[$idx]);
}

sub next_menu {
    my ($self) = @_;
    my @menus = qw(f e s v);
    my $idx = 0;
    for my $i (0..$#menus) {
        $idx = $i if $menus[$i] eq $self->{menu_open};
    }
    $idx = ($idx + 1) % @menus;
    $self->open_menu($menus[$idx]);
}

sub menu_move {
    my ($self, $direction) = @_;

    my @items = @{$self->_menu_items()};
    return unless @items;

    my $current = $self->{menu_selected};
    my $new_idx = $current;

    # Move in direction, skipping separators
    while (1) {
        $new_idx += $direction;

        # Clamp to bounds
        if ($new_idx < 0) {
            $new_idx = 0;
            last;
        }
        if ($new_idx >= @items) {
            $new_idx = $#items;
            last;
        }

        # Stop if not a separator
        last if $items[$new_idx] ne '-';
    }

    $self->{menu_selected} = $new_idx;
}

# =============================================================================
# Menu Items and Execution
# =============================================================================

sub _menu_items {
    my ($self) = @_;
    # Use shared menu definitions from Renderer (single source of truth)
    return Zepto::Renderer->get_menu_actions($self->{menu_open});
}

sub execute_menu_item {
    my ($self) = @_;

    my $idx = $self->{menu_selected};
    my @items = @{$self->_menu_items()};
    return unless $idx < @items;

    my $action = $items[$idx];
    return if $action eq '-';  # Separator

    $self->close_menu();

    # Execute action
    if    ($action eq 'new')        { $self->cmd_new_file(); }
    elsif ($action eq 'open')       { $self->cmd_open_file(); }
    elsif ($action eq 'save')       { $self->cmd_save(); }
    elsif ($action eq 'save_quit')  { $self->cmd_save_and_quit(); }
    elsif ($action eq 'quit')       { $self->cmd_quit(); }
    elsif ($action eq 'undo')       { $self->cmd_undo(); }
    elsif ($action eq 'redo')       { $self->cmd_redo(); }
    elsif ($action eq 'cut')        { $self->cmd_cut(); }
    elsif ($action eq 'copy')       { $self->cmd_copy(); }
    elsif ($action eq 'paste')      { $self->cmd_paste(); }
    elsif ($action eq 'move_line_up')   { $self->do_move_line_up(); }
    elsif ($action eq 'move_line_down') { $self->do_move_line_down(); }
    elsif ($action eq 'dup_line_up')    { $self->do_duplicate_line_up(); }
    elsif ($action eq 'dup_line_down')  { $self->do_duplicate_line_down(); }
    elsif ($action eq 'select_all') { $self->cmd_select_all(); }
    elsif ($action eq 'find')       { $self->cmd_find(); }
    elsif ($action eq 'find_next')  { $self->cmd_find_next(); }
    elsif ($action eq 'find_prev')  { $self->cmd_find_prev(); }
    elsif ($action eq 'replace')    { $self->cmd_replace(); }
    elsif ($action eq 'goto')       { $self->cmd_goto_line(); }
    elsif ($action eq 'toggle_theme') { $self->cmd_toggle_theme(); }
}

1;
