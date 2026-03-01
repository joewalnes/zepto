package Zepto::Editor::Palette;
# =============================================================================
# Editor Palette Handling - Command palette overlay
# =============================================================================
#
# This module defines palette-related methods for the Zepto::Editor class.
# Handles opening/closing the command palette, type-to-filter, navigation,
# and executing commands.
# =============================================================================

use strict;
use warnings;
use utf8;

# Define methods in Zepto::Editor's namespace
package Zepto::Editor;

use Zepto::CommandRegistry;

# =============================================================================
# Palette State
# =============================================================================

sub cmd_open_palette {
    my ($self) = @_;

    # Don't open palette during input-focused states
    return if $self->{state} eq STATE_FOOTER_INPUT;
    return if $self->{state} eq STATE_PROMPT;
    return if $self->{state} eq STATE_FIND;
    return if $self->{state} eq STATE_DIALOG;

    $self->{state} = STATE_PALETTE;
    $self->{palette_query} = '';
    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->_palette_update_filtered();
}

sub close_palette {
    my ($self) = @_;
    $self->{state} = STATE_EDITING;
    $self->{palette_query} = '';
    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->{palette_filtered} = [];
}

# =============================================================================
# Palette Event Handling
# =============================================================================

sub handle_palette_event {
    my ($self, $event) = @_;

    my $type = $event->{type};

    if ($type eq 'key') {
        my $key = $event->{key};

        if ($key eq 'escape') {
            $self->close_palette();
        }
        elsif ($key eq 'enter') {
            $self->_palette_execute_selected();
        }
        elsif ($key eq 'up') {
            $self->_palette_move_cursor(-1);
        }
        elsif ($key eq 'down') {
            $self->_palette_move_cursor(1);
        }
        elsif ($key eq 'backspace') {
            if (length($self->{palette_query}) > 0) {
                $self->{palette_query} = substr($self->{palette_query}, 0, -1);
                $self->{palette_cursor} = 0;
                $self->{palette_scroll} = 0;
                $self->_palette_update_filtered();
            }
        }
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');
        my $alt = Zepto::InputParser::has_modifier($event, 'alt');

        if ($ctrl) {
            # Check if ctrl+char matches a command shortcut — execute directly
            my $matched = $self->_palette_try_shortcut('ctrl', $char);
            return if $matched;

            # Ctrl+Space while palette is open closes it
            if ($char eq ' ') {
                $self->close_palette();
                return;
            }
        }
        elsif ($alt) {
            # Check if alt+char matches a command shortcut
            my $matched = $self->_palette_try_shortcut('alt', $char);
            return if $matched;
        }
        else {
            # Printable character — append to query
            $self->{palette_query} .= $char;
            $self->{palette_cursor} = 0;
            $self->{palette_scroll} = 0;
            $self->_palette_update_filtered();
        }
    }
    elsif ($type eq 'mouse') {
        $self->_handle_palette_mouse($event);
    }
}

# =============================================================================
# Internal Helpers
# =============================================================================

sub _palette_update_filtered {
    my ($self) = @_;
    my @filtered = Zepto::CommandRegistry->filter_commands($self->{palette_query});
    $self->{palette_filtered} = \@filtered;

    # Clamp cursor to valid range
    my $max = scalar(@filtered) - 1;
    $max = 0 if $max < 0;
    $self->{palette_cursor} = $max if $self->{palette_cursor} > $max;
}

sub _palette_move_cursor {
    my ($self, $delta) = @_;
    my $count = scalar @{$self->{palette_filtered}};
    return unless $count > 0;

    my $new_pos = $self->{palette_cursor} + $delta;
    $new_pos = 0 if $new_pos < 0;
    $new_pos = $count - 1 if $new_pos >= $count;
    $self->{palette_cursor} = $new_pos;

    # Ensure cursor is visible within scroll window
    $self->_palette_ensure_visible();
}

sub _palette_ensure_visible {
    my ($self) = @_;
    my $cursor = $self->{palette_cursor};
    my $scroll = $self->{palette_scroll};

    # Visible rows in the palette (will be computed from terminal size during render,
    # but use a reasonable default for scroll management)
    my $visible = $self->{palette_visible_rows} // 15;

    if ($cursor < $scroll) {
        $self->{palette_scroll} = $cursor;
    }
    elsif ($cursor >= $scroll + $visible) {
        $self->{palette_scroll} = $cursor - $visible + 1;
    }
}

sub _palette_execute_selected {
    my ($self) = @_;

    my $filtered = $self->{palette_filtered};
    return unless @$filtered;

    my $cmd = $filtered->[$self->{palette_cursor}];
    return unless $cmd;

    if ($cmd->{type} eq 'toggle') {
        # Toggle commands: execute and stay open (update state live)
        Zepto::CommandRegistry->execute($self, $cmd->{id});
        # Re-filter to update toggle state display
        $self->_palette_update_filtered();
    }
    else {
        # Action commands: execute and close
        $self->close_palette();
        Zepto::CommandRegistry->execute($self, $cmd->{id});
    }
}

sub _palette_try_shortcut {
    my ($self, $modifier, $char) = @_;
    $char = lc($char);

    my @all = Zepto::CommandRegistry->all_commands();
    for my $cmd (@all) {
        my $shortcut = $cmd->{shortcut} // '';
        my $expected;
        if ($modifier eq 'ctrl') {
            $expected = Zepto::CommandRegistry::SYM_CTRL . uc($char);
        } elsif ($modifier eq 'alt') {
            $expected = Zepto::CommandRegistry::SYM_ALT . uc($char);
        } else {
            next;
        }

        if ($shortcut eq $expected) {
            if ($cmd->{type} eq 'toggle') {
                Zepto::CommandRegistry->execute($self, $cmd->{id});
                $self->_palette_update_filtered();
            } else {
                $self->close_palette();
                Zepto::CommandRegistry->execute($self, $cmd->{id});
            }
            return 1;
        }
    }
    return 0;
}

sub _handle_palette_mouse {
    my ($self, $event) = @_;

    my $action = $event->{action};

    if ($action eq 'press') {
        my $x = $event->{x};
        my $y = $event->{y};

        # Check if click is inside palette area
        my @buttons = Zepto::Renderer::get_palette_buttons();
        for my $btn (@buttons) {
            if ($y == $btn->{y} && $x >= $btn->{x_start} && $x <= $btn->{x_end}) {
                my $idx = $btn->{index};
                $self->{palette_cursor} = $idx;
                $self->_palette_execute_selected();
                return;
            }
        }

        # Click outside palette → close
        $self->close_palette();
    }
    elsif ($action eq 'scroll_up') {
        $self->_palette_move_cursor(-3);
    }
    elsif ($action eq 'scroll_down') {
        $self->_palette_move_cursor(3);
    }
}

# =============================================================================
# Status Bar Click Handling
# =============================================================================

sub handle_status_bar_click {
    my ($self, $x) = @_;

    my @buttons = Zepto::Renderer::get_status_buttons();
    for my $btn (@buttons) {
        if ($x >= $btn->{x_start} && $x <= $btn->{x_end}) {
            my $cmd_id = $btn->{command_id};
            if ($cmd_id eq 'open_palette') {
                $self->cmd_open_palette();
            } else {
                Zepto::CommandRegistry->execute($self, $cmd_id);
            }
            return;
        }
    }
}

1;
