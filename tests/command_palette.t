#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Zepto::Editor qw(STATE_EDITING STATE_PALETTE STATE_FIND STATE_FOOTER_INPUT STATE_PROMPT STATE_DIALOG);
use Zepto::InputParser;

# =============================================================================
# Command Palette unit tests
# =============================================================================

# Helper: create a minimal editor for testing
sub make_editor {
    # Create a mock terminal that doesn't do real I/O
    my $prefs = Zepto::Preferences->new();
    my $editor = Zepto::Editor->new(
        terminal => _MockTerminal->new(),
        prefs    => $prefs,
    );
    # Initialize with a blank document so we have an active view
    $editor->cmd_new_file();
    return $editor;
}

# Mock terminal for tests
package _MockTerminal {
    sub new { bless { size => [24, 80] }, shift }
    sub get_size { return @{$_[0]->{size}} }
    sub write { }
    sub setup_raw_mode { }
    sub restore_mode { }
    sub flush { }
}

package main;

# =============================================================================
# State transitions
# =============================================================================

subtest 'cmd_open_palette sets STATE_PALETTE' => sub {
    my $editor = make_editor();
    is($editor->{state}, STATE_EDITING, 'Starts in editing state');
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PALETTE, 'State is palette after open');
    is($editor->{palette}{palette_widget}->value(), '', 'Query starts empty');
    # Cursor starts on first command (skipping section header at index 0)
    is($editor->{palette}{palette_cursor}, 1, 'Cursor starts at 1 (after section header)');
    ok(scalar @{$editor->{palette}{palette_filtered}} > 0, 'Filtered list populated');
};

subtest 'close_palette returns to STATE_EDITING' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PALETTE, 'Palette is open');
    $editor->close_palette();
    is($editor->{state}, STATE_EDITING, 'Returns to editing');
    ok(!defined $editor->{palette}{palette_widget}, 'Widget cleared (palette closed)');
    is(scalar @{$editor->{palette}{palette_filtered}}, 0, 'Filtered list cleared');
};

subtest 'Escape closes palette' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    $editor->handle_event({ type => 'key', key => 'escape', modifiers => [] });
    is($editor->{state}, STATE_EDITING, 'Escape returns to editing');
};

# =============================================================================
# Palette opens from any modal state (global shortcut)
# =============================================================================

subtest 'cmd_open_palette opens from STATE_FIND' => sub {
    my $editor = make_editor();
    $editor->{state} = STATE_FIND;
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PALETTE, 'Palette opens from find state');
};

subtest 'cmd_open_palette opens from STATE_FOOTER_INPUT' => sub {
    my $editor = make_editor();
    $editor->{state} = STATE_FOOTER_INPUT;
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PALETTE, 'Palette opens from footer_input state');
};

subtest 'cmd_open_palette opens from STATE_PROMPT' => sub {
    my $editor = make_editor();
    $editor->{state} = STATE_PROMPT;
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PALETTE, 'Palette opens from prompt state');
};

subtest 'cmd_open_palette opens from STATE_DIALOG' => sub {
    my $editor = make_editor();
    $editor->{state} = STATE_DIALOG;
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PALETTE, 'Palette opens from dialog state');
};

# =============================================================================
# Type-to-filter
# =============================================================================

subtest 'Typing narrows filtered list' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    my $all_count = scalar @{$editor->{palette}{palette_filtered}};
    ok($all_count > 10, "All commands listed: $all_count");

    # Type 's'
    $editor->handle_event({ type => 'char', char => 's', modifiers => [] });
    is($editor->{palette}{palette_widget}->value(), 's', 'Query updated to "s"');
    my $s_count = scalar @{$editor->{palette}{palette_filtered}};
    ok($s_count < $all_count, "Filtered list narrowed: $s_count < $all_count");
    ok($s_count > 0, 'Still has results');

    # Type 'ave' to make 'save'
    $editor->handle_event({ type => 'char', char => 'a', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'v', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'e', modifiers => [] });
    is($editor->{palette}{palette_widget}->value(), 'save', 'Query is "save"');
    my $save_count = scalar @{$editor->{palette}{palette_filtered}};
    ok($save_count >= 1, 'Save command found');
    is($editor->{palette}{palette_filtered}[0]{id}, 'save', 'Save is top result');
};

subtest 'Backspace removes characters from query' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    $editor->handle_event({ type => 'char', char => 'a', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'b', modifiers => [] });
    is($editor->{palette}{palette_widget}->value(), 'ab', 'Query is "ab"');

    $editor->handle_event({ type => 'key', key => 'backspace', modifiers => [] });
    is($editor->{palette}{palette_widget}->value(), 'a', 'Backspace removed last char');

    $editor->handle_event({ type => 'key', key => 'backspace', modifiers => [] });
    is($editor->{palette}{palette_widget}->value(), '', 'Backspace cleared query');
    # Empty query shows all commands + section headers (4 sections)
    my $cmd_count = scalar(Zepto::CommandRegistry->all_commands());
    my $section_count = scalar(Zepto::CommandRegistry->section_order());
    is(scalar @{$editor->{palette}{palette_filtered}}, $cmd_count + $section_count,
       'Empty query shows all commands plus section headers');
};

# =============================================================================
# Arrow key navigation
# =============================================================================

subtest 'Arrow keys move cursor' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    # Cursor starts at 1 (first command, after FILE header at 0)
    is($editor->{palette}{palette_cursor}, 1, 'Cursor starts at 1 (first command)');

    $editor->handle_event({ type => 'key', key => 'down', modifiers => [] });
    is($editor->{palette}{palette_cursor}, 2, 'Down moves to 2');

    $editor->handle_event({ type => 'key', key => 'down', modifiers => [] });
    is($editor->{palette}{palette_cursor}, 3, 'Down moves to 3');

    $editor->handle_event({ type => 'key', key => 'up', modifiers => [] });
    is($editor->{palette}{palette_cursor}, 2, 'Up moves back to 2');
};

subtest 'Cursor clamps at boundaries' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Move up from first command - should stay at first command (skip header)
    $editor->handle_event({ type => 'key', key => 'up', modifiers => [] });
    is($editor->{palette}{palette_cursor}, 1, 'Up from first command stays at first command (skips header)');

    # Move to last item
    my $max = scalar @{$editor->{palette}{palette_filtered}} - 1;
    $editor->{palette}{palette_cursor} = $max;
    $editor->handle_event({ type => 'key', key => 'down', modifiers => [] });
    is($editor->{palette}{palette_cursor}, $max, 'Down from last stays at last');
};

# =============================================================================
# Enter executes selected command
# =============================================================================

subtest 'Enter on action command closes palette' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Filter to 'undo' (an action command that doesn't trigger another state)
    $editor->handle_event({ type => 'char', char => 'u', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'n', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'd', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'o', modifiers => [] });

    is($editor->{palette}{palette_filtered}[0]{id}, 'undo', 'Undo is top');
    is($editor->{palette}{palette_filtered}[0]{type}, 'action', 'Undo is action type');

    $editor->handle_event({ type => 'key', key => 'enter', modifiers => [] });
    is($editor->{state}, STATE_EDITING, 'Action command closes palette');
};

subtest 'Enter on toggle command stays open' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Filter to 'word wrap' (a toggle command)
    $editor->handle_event({ type => 'char', char => 'w', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'r', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'a', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'p', modifiers => [] });

    my @toggles = grep { $_->{type} eq 'toggle' } @{$editor->{palette}{palette_filtered}};
    ok(scalar @toggles > 0, 'Found toggle commands matching "wrap"');

    # Move cursor to first toggle result
    for my $i (0 .. $#{$editor->{palette}{palette_filtered}}) {
        if ($editor->{palette}{palette_filtered}[$i]{type} eq 'toggle') {
            $editor->{palette}{palette_cursor} = $i;
            last;
        }
    }

    $editor->handle_event({ type => 'key', key => 'enter', modifiers => [] });
    is($editor->{state}, STATE_PALETTE, 'Toggle command keeps palette open');
};

# =============================================================================
# Ctrl+Space toggle
# =============================================================================

subtest 'Ctrl+Space in palette closes it' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PALETTE, 'Palette open');

    $editor->handle_event({ type => 'char', char => ' ', modifiers => ['ctrl'] });
    is($editor->{state}, STATE_EDITING, 'Ctrl+Space closes palette');
};

# Regression test for bugs.md P2 "Ctrl+Space (open palette) can be
# silently dropped when it isn't the very first key sent" / QA-REG-169.
# Root cause: handle_ctrl_char's space-handler treated "one word character
# before the cursor" as sufficient reason to try the completion menu
# instead of the palette, but Completion::Controller::trigger() requires a
# 2+ char prefix to produce anything — with a 1-char prefix, trigger()
# dismisses immediately, is_active() stays false, and the old code
# returned right there without ever falling back to cmd_open_palette(),
# so Ctrl+Space did nothing at all.
subtest 'Ctrl+Space opens the palette when mid-word but no completion is available' => sub {
    my $editor = make_editor();
    is($editor->{state}, STATE_EDITING, 'Starts in editing state');

    my $doc  = $editor->active_doc();
    my $view = $editor->active_view();
    $doc->insert(0, 'hello world');
    $view->set_cursor(0, 1);  # cursor right after the single word char 'h'

    $editor->handle_event({ type => 'char', char => ' ', modifiers => ['ctrl'] });
    is($editor->{state}, STATE_PALETTE,
        'Ctrl+Space falls back to opening the palette (1-char prefix has no real completion)');
    is($doc->get_text(), 'hello world', 'document text is untouched');
};

# =============================================================================
# Event routing
# =============================================================================

subtest 'handle_event routes to palette handler' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Type a character - should go through handle_event → handle_palette_event
    $editor->handle_event({ type => 'char', char => 'x', modifiers => [] });
    is($editor->{palette}{palette_widget}->value(), 'x', 'Event routed to palette handler');
};

subtest 'Typing resets cursor to 0' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    $editor->{palette}{palette_cursor} = 5;

    $editor->handle_event({ type => 'char', char => 'z', modifiers => [] });
    is($editor->{palette}{palette_cursor}, 0, 'Typing resets cursor to 0');
};

# =============================================================================
# Mouse handling
# =============================================================================

subtest 'Mouse click outside palette closes it' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Click at 1,1 which is outside the centered palette
    $editor->handle_event({
        type    => 'mouse',
        action  => 'press',
        x       => 1,
        y       => 1,
        modifiers => [],
    });
    is($editor->{state}, STATE_EDITING, 'Click outside closes palette');
};

# =============================================================================
# Palette filtered list integrity
# =============================================================================

subtest 'Filtered list contains valid commands and section headers' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    my $header_count = 0;
    my $cmd_count = 0;
    for my $item (@{$editor->{palette}{palette_filtered}}) {
        if ($item->{_is_header}) {
            ok(defined $item->{label}, "Header has label: $item->{label}");
            $header_count++;
        } else {
            ok(defined $item->{id}, "Command has id: $item->{id}");
            ok(defined $item->{label}, "Command has label: $item->{label}");
            ok(defined $item->{method}, "Command has method: $item->{method}");
            $cmd_count++;
        }
    }
    is($header_count, scalar(Zepto::CommandRegistry->section_order()), 'Has expected section headers');
    is($cmd_count, scalar(Zepto::CommandRegistry->all_commands()), 'Has all commands');
};

subtest 'Nonsense query returns empty filtered list' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    for my $c (split //, 'xyzxyzxyz') {
        $editor->handle_event({ type => 'char', char => $c, modifiers => [] });
    }
    is(scalar @{$editor->{palette}{palette_filtered}}, 0, 'Nonsense query returns 0 results');
};

# =============================================================================
# Header-skipping navigation (direct _palette_skip_headers tests)
# =============================================================================

subtest 'Arrow down skips section headers between items' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Build a controlled filtered list: [item, header, item, header, item]
    $editor->{palette}{palette_filtered} = [
        { id => 'a', label => 'A', method => sub {}, type => 'action' },
        { _is_header => 1, label => 'Section 2' },
        { id => 'b', label => 'B', method => sub {}, type => 'action' },
        { _is_header => 1, label => 'Section 3' },
        { id => 'c', label => 'C', method => sub {}, type => 'action' },
    ];
    $editor->{palette}{palette_cursor} = 0;
    $editor->{palette}{palette_scroll} = 0;

    # Move down from item 0 → should land on 1 (header) → skip to 2 (item)
    $editor->{palette}->_palette_move_cursor(1);
    is($editor->{palette}{palette_cursor}, 2, 'Down from 0 skips header at 1, lands on 2');

    # Move down again → should land on 3 (header) → skip to 4 (item)
    $editor->{palette}->_palette_move_cursor(1);
    is($editor->{palette}{palette_cursor}, 4, 'Down from 2 skips header at 3, lands on 4');
};

subtest 'Arrow up skips section headers between items' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    $editor->{palette}{palette_filtered} = [
        { id => 'a', label => 'A', method => sub {}, type => 'action' },
        { _is_header => 1, label => 'Section 2' },
        { id => 'b', label => 'B', method => sub {}, type => 'action' },
    ];
    $editor->{palette}{palette_cursor} = 2;
    $editor->{palette}{palette_scroll} = 0;

    # Move up from item 2 → lands on 1 (header) → skip back to 0 (item)
    $editor->{palette}->_palette_move_cursor(-1);
    is($editor->{palette}{palette_cursor}, 0, 'Up from 2 skips header at 1, lands on 0');
};

subtest 'Navigation skips consecutive headers' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Two consecutive headers between items
    $editor->{palette}{palette_filtered} = [
        { id => 'a', label => 'A', method => sub {}, type => 'action' },
        { _is_header => 1, label => 'H1' },
        { _is_header => 1, label => 'H2' },
        { id => 'b', label => 'B', method => sub {}, type => 'action' },
    ];
    $editor->{palette}{palette_cursor} = 0;
    $editor->{palette}{palette_scroll} = 0;

    # Down from 0 → 1 (header) → skip forward → 2 (header) → skip → 3 (item)
    $editor->{palette}->_palette_move_cursor(1);
    is($editor->{palette}{palette_cursor}, 3, 'Down skips two consecutive headers');
};

subtest 'Header at start: cursor skips forward to first item' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    $editor->{palette}{palette_filtered} = [
        { _is_header => 1, label => 'Section' },
        { id => 'a', label => 'A', method => sub {}, type => 'action' },
        { id => 'b', label => 'B', method => sub {}, type => 'action' },
    ];
    $editor->{palette}{palette_cursor} = 1;
    $editor->{palette}{palette_scroll} = 0;

    # Try moving up from item at 1 → lands on 0 (header) → reverses to 1
    $editor->{palette}->_palette_move_cursor(-1);
    is($editor->{palette}{palette_cursor}, 1, 'Up past header at start reverses to first item');
};

subtest 'Header at end: cursor stays on last item' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    $editor->{palette}{palette_filtered} = [
        { id => 'a', label => 'A', method => sub {}, type => 'action' },
        { id => 'b', label => 'B', method => sub {}, type => 'action' },
        { _is_header => 1, label => 'Trailing Section' },
    ];
    $editor->{palette}{palette_cursor} = 1;
    $editor->{palette}{palette_scroll} = 0;

    # Down from 1 → lands on 2 (header at end) → reverses to 1
    $editor->{palette}->_palette_move_cursor(1);
    is($editor->{palette}{palette_cursor}, 1, 'Down into trailing header reverses to last item');
};

done_testing();
