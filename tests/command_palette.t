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
    is($editor->{palette_query}, '', 'Query starts empty');
    is($editor->{palette_cursor}, 0, 'Cursor starts at 0');
    ok(scalar @{$editor->{palette_filtered}} > 0, 'Filtered list populated');
};

subtest 'close_palette returns to STATE_EDITING' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PALETTE, 'Palette is open');
    $editor->close_palette();
    is($editor->{state}, STATE_EDITING, 'Returns to editing');
    is($editor->{palette_query}, '', 'Query cleared');
    is(scalar @{$editor->{palette_filtered}}, 0, 'Filtered list cleared');
};

subtest 'Escape closes palette' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    $editor->handle_event({ type => 'key', key => 'escape', modifiers => [] });
    is($editor->{state}, STATE_EDITING, 'Escape returns to editing');
};

# =============================================================================
# Palette does NOT open during certain states
# =============================================================================

subtest 'cmd_open_palette blocked during STATE_FIND' => sub {
    my $editor = make_editor();
    $editor->{state} = STATE_FIND;
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_FIND, 'State unchanged - still find');
};

subtest 'cmd_open_palette blocked during STATE_FOOTER_INPUT' => sub {
    my $editor = make_editor();
    $editor->{state} = STATE_FOOTER_INPUT;
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_FOOTER_INPUT, 'State unchanged - still footer_input');
};

subtest 'cmd_open_palette blocked during STATE_PROMPT' => sub {
    my $editor = make_editor();
    $editor->{state} = STATE_PROMPT;
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_PROMPT, 'State unchanged - still prompt');
};

subtest 'cmd_open_palette blocked during STATE_DIALOG' => sub {
    my $editor = make_editor();
    $editor->{state} = STATE_DIALOG;
    $editor->cmd_open_palette();
    is($editor->{state}, STATE_DIALOG, 'State unchanged - still dialog');
};

# =============================================================================
# Type-to-filter
# =============================================================================

subtest 'Typing narrows filtered list' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    my $all_count = scalar @{$editor->{palette_filtered}};
    ok($all_count > 10, "All commands listed: $all_count");

    # Type 's'
    $editor->handle_event({ type => 'char', char => 's', modifiers => [] });
    is($editor->{palette_query}, 's', 'Query updated to "s"');
    my $s_count = scalar @{$editor->{palette_filtered}};
    ok($s_count < $all_count, "Filtered list narrowed: $s_count < $all_count");
    ok($s_count > 0, 'Still has results');

    # Type 'ave' to make 'save'
    $editor->handle_event({ type => 'char', char => 'a', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'v', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'e', modifiers => [] });
    is($editor->{palette_query}, 'save', 'Query is "save"');
    my $save_count = scalar @{$editor->{palette_filtered}};
    ok($save_count >= 1, 'Save command found');
    is($editor->{palette_filtered}[0]{id}, 'save', 'Save is top result');
};

subtest 'Backspace removes characters from query' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    $editor->handle_event({ type => 'char', char => 'a', modifiers => [] });
    $editor->handle_event({ type => 'char', char => 'b', modifiers => [] });
    is($editor->{palette_query}, 'ab', 'Query is "ab"');

    $editor->handle_event({ type => 'key', key => 'backspace', modifiers => [] });
    is($editor->{palette_query}, 'a', 'Backspace removed last char');

    $editor->handle_event({ type => 'key', key => 'backspace', modifiers => [] });
    is($editor->{palette_query}, '', 'Backspace cleared query');
    is(scalar @{$editor->{palette_filtered}}, scalar(Zepto::CommandRegistry->all_commands()),
       'Empty query shows all commands');
};

# =============================================================================
# Arrow key navigation
# =============================================================================

subtest 'Arrow keys move cursor' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    is($editor->{palette_cursor}, 0, 'Cursor starts at 0');

    $editor->handle_event({ type => 'key', key => 'down', modifiers => [] });
    is($editor->{palette_cursor}, 1, 'Down moves to 1');

    $editor->handle_event({ type => 'key', key => 'down', modifiers => [] });
    is($editor->{palette_cursor}, 2, 'Down moves to 2');

    $editor->handle_event({ type => 'key', key => 'up', modifiers => [] });
    is($editor->{palette_cursor}, 1, 'Up moves back to 1');
};

subtest 'Cursor clamps at boundaries' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Move up from 0 - should stay at 0
    $editor->handle_event({ type => 'key', key => 'up', modifiers => [] });
    is($editor->{palette_cursor}, 0, 'Up from 0 stays at 0');

    # Move to last item
    my $max = scalar @{$editor->{palette_filtered}} - 1;
    $editor->{palette_cursor} = $max;
    $editor->handle_event({ type => 'key', key => 'down', modifiers => [] });
    is($editor->{palette_cursor}, $max, 'Down from last stays at last');
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

    is($editor->{palette_filtered}[0]{id}, 'undo', 'Undo is top');
    is($editor->{palette_filtered}[0]{type}, 'action', 'Undo is action type');

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

    my @toggles = grep { $_->{type} eq 'toggle' } @{$editor->{palette_filtered}};
    ok(scalar @toggles > 0, 'Found toggle commands matching "wrap"');

    # Move cursor to first toggle result
    for my $i (0 .. $#{$editor->{palette_filtered}}) {
        if ($editor->{palette_filtered}[$i]{type} eq 'toggle') {
            $editor->{palette_cursor} = $i;
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

# =============================================================================
# Event routing
# =============================================================================

subtest 'handle_event routes to palette handler' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    # Type a character - should go through handle_event → handle_palette_event
    $editor->handle_event({ type => 'char', char => 'x', modifiers => [] });
    is($editor->{palette_query}, 'x', 'Event routed to palette handler');
};

subtest 'Typing resets cursor to 0' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();
    $editor->{palette_cursor} = 5;

    $editor->handle_event({ type => 'char', char => 'z', modifiers => [] });
    is($editor->{palette_cursor}, 0, 'Typing resets cursor to 0');
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

subtest 'Filtered list contains valid commands' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    for my $cmd (@{$editor->{palette_filtered}}) {
        ok(defined $cmd->{id}, "Command has id: $cmd->{id}");
        ok(defined $cmd->{label}, "Command has label: $cmd->{label}");
        ok(defined $cmd->{method}, "Command has method: $cmd->{method}");
    }
};

subtest 'Nonsense query returns empty filtered list' => sub {
    my $editor = make_editor();
    $editor->cmd_open_palette();

    for my $c (split //, 'xyzxyzxyz') {
        $editor->handle_event({ type => 'char', char => $c, modifiers => [] });
    }
    is(scalar @{$editor->{palette_filtered}}, 0, 'Nonsense query returns 0 results');
};

done_testing();
