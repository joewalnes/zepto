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
use Zepto::InputWidget;

# =============================================================================
# Palette State
# =============================================================================

sub cmd_open_palette {
    my ($self) = @_;

    # Don't open palette during input-focused states
    return if $self->{state} eq 'footer_input';
    return if $self->{state} eq 'prompt';
    return if $self->{state} eq 'find';
    return if $self->{state} eq 'dialog';

    $self->{state} = 'palette';
    $self->{palette_widget} = Zepto::InputWidget->new();
    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->_palette_update_filtered();
}

sub close_palette {
    my ($self) = @_;
    $self->{state} = 'editing';
    $self->{palette_widget} = undef;
    $self->{palette_cursor} = 0;
    $self->{palette_scroll} = 0;
    $self->{palette_filtered} = [];
}

# =============================================================================
# Palette Event Handling
# =============================================================================

sub handle_palette_event {
    my ($self, $event) = @_;

    my $type   = $event->{type};
    my $widget = $self->{palette_widget};

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
        else {
            # Delegate cursor/editing keys to widget
            my $old_query = $widget->value();
            $widget->handle_event($event, \$self->{clipboard});
            if ($widget->value() ne $old_query) {
                $self->{palette_cursor} = 0;
                $self->{palette_scroll} = 0;
                $self->_palette_update_filtered();
            }
        }
    }
    elsif ($type eq 'char') {
        my $char = $event->{char};
        my $ctrl = Zepto::InputParser::has_modifier($event, 'ctrl');
        my $alt  = Zepto::InputParser::has_modifier($event, 'alt');

        if ($ctrl) {
            # Check if ctrl+char matches a command shortcut — execute directly
            my $matched = $self->_palette_try_shortcut('ctrl', $char);
            return if $matched;

            # Ctrl+Space while palette is open closes it
            if ($char eq ' ') {
                $self->close_palette();
                return;
            }

            # Delegate Ctrl+A / other editing to widget
            my $old_query = $widget->value();
            $widget->handle_event($event);
            if ($widget->value() ne $old_query) {
                $self->{palette_cursor} = 0;
                $self->{palette_scroll} = 0;
                $self->_palette_update_filtered();
            }
        }
        elsif ($alt) {
            # Check if alt+char matches a command shortcut
            my $matched = $self->_palette_try_shortcut('alt', $char);
            return if $matched;
        }
        else {
            # Printable character — append to query via widget
            my $old_query = $widget->value();
            $widget->handle_event($event);
            if ($widget->value() ne $old_query) {
                $self->{palette_cursor} = 0;
                $self->{palette_scroll} = 0;
                $self->_palette_update_filtered();
            }
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
    my $query   = $self->{palette_widget} ? $self->{palette_widget}->value() : '';
    my @filtered = Zepto::CommandRegistry->filter_commands($query);

    # When no query, insert section headers before each group
    if (length($query) == 0) {
        my @with_headers;
        my $current_section = '';
        for my $cmd (@filtered) {
            if (($cmd->{section} // '') ne $current_section) {
                $current_section = $cmd->{section};
                push @with_headers, { _is_header => 1, label => $current_section };
            }
            push @with_headers, $cmd;
        }
        @filtered = @with_headers;
    }

    $self->{palette_filtered} = \@filtered;

    # Clamp cursor to valid range
    my $max = scalar(@filtered) - 1;
    $max = 0 if $max < 0;
    $self->{palette_cursor} = $max if $self->{palette_cursor} > $max;

    # Ensure cursor is not on a section header
    $self->_palette_skip_headers(1);
}

sub _palette_move_cursor {
    my ($self, $delta) = @_;
    my $count = scalar @{$self->{palette_filtered}};
    return unless $count > 0;

    my $new_pos = $self->{palette_cursor} + $delta;
    $new_pos = 0 if $new_pos < 0;
    $new_pos = $count - 1 if $new_pos >= $count;
    $self->{palette_cursor} = $new_pos;

    # Skip section headers in the direction of movement
    $self->_palette_skip_headers($delta > 0 ? 1 : -1);

    # Ensure cursor is visible within scroll window
    $self->_palette_ensure_visible();
}

sub _palette_skip_headers {
    my ($self, $direction) = @_;
    my $filtered = $self->{palette_filtered};
    my $count = scalar @$filtered;
    return unless $count > 0;

    $direction = 1 unless defined $direction;
    my $cursor = $self->{palette_cursor};

    # Move past headers in the given direction
    while ($cursor >= 0 && $cursor < $count && $filtered->[$cursor]{_is_header}) {
        $cursor += $direction;
    }

    # If we went off the end, try the other direction
    if ($cursor < 0 || $cursor >= $count) {
        $cursor = $self->{palette_cursor};
        $direction = -$direction;
        while ($cursor >= 0 && $cursor < $count && $filtered->[$cursor]{_is_header}) {
            $cursor += $direction;
        }
    }

    $cursor = 0 if $cursor < 0;
    $cursor = $count - 1 if $cursor >= $count;
    $self->{palette_cursor} = $cursor;
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
    return if $cmd->{_is_header};  # Section headers are not executable

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
