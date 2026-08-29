#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Zepto::CommandRegistry;

# =============================================================================
# CommandRegistry unit tests
# =============================================================================

subtest 'All commands have unique IDs' => sub {
    my @cmds = Zepto::CommandRegistry->all_commands();
    my %seen;
    for my $cmd (@cmds) {
        ok(!$seen{$cmd->{id}}, "ID '$cmd->{id}' is unique");
        $seen{$cmd->{id}} = 1;
    }
    ok(scalar @cmds > 20, 'At least 20 commands defined');
};

subtest 'All commands have required fields' => sub {
    my @cmds = Zepto::CommandRegistry->all_commands();
    for my $cmd (@cmds) {
        ok(defined $cmd->{id},       "cmd '$cmd->{id}': has id");
        ok(defined $cmd->{label},    "cmd '$cmd->{id}': has label");
        ok(defined $cmd->{icon},     "cmd '$cmd->{id}': has icon");
        ok(defined $cmd->{shortcut}, "cmd '$cmd->{id}': has shortcut");
        ok(defined $cmd->{section},  "cmd '$cmd->{id}': has section");
        ok(defined $cmd->{type},     "cmd '$cmd->{id}': has type");
        ok(defined $cmd->{method},   "cmd '$cmd->{id}': has method");
        like($cmd->{type}, qr/^(action|toggle|setting)$/, "cmd '$cmd->{id}': valid type");
    }
};

subtest 'commands_by_section groups correctly' => sub {
    my @sections = Zepto::CommandRegistry->commands_by_section();
    ok(scalar @sections >= 4, 'At least 4 sections');

    my %seen_sections;
    for my $sec (@sections) {
        ok(defined $sec->{name}, "Section has name: $sec->{name}");
        ok(ref $sec->{items} eq 'ARRAY', "Section '$sec->{name}' has items array");
        ok(scalar @{$sec->{items}} > 0, "Section '$sec->{name}' is not empty");
        $seen_sections{$sec->{name}} = 1;
    }

    ok($seen_sections{'FILE'}, 'Has FILE section');
    ok($seen_sections{'EDIT'}, 'Has EDIT section');
    ok($seen_sections{'NAVIGATE'}, 'Has NAVIGATE section');
    ok($seen_sections{'VIEW'}, 'Has VIEW section');
};

subtest 'find_command lookup' => sub {
    my $cmd = Zepto::CommandRegistry->find_command('save');
    ok(defined $cmd, 'Found save command');
    is($cmd->{label}, 'Save', 'Correct label');
    is($cmd->{method}, 'cmd_save', 'Correct method');

    my $missing = Zepto::CommandRegistry->find_command('nonexistent');
    is($missing, undef, 'Returns undef for missing command');
};

subtest 'filter_commands - basic' => sub {
    my @results = Zepto::CommandRegistry->filter_commands('save');
    ok(scalar @results > 0, 'Found results for "save"');
    is($results[0]->{id}, 'save', 'Save is top result');
};

subtest 'filter_commands - fuzzy matching' => sub {
    my @results = Zepto::CommandRegistry->filter_commands('wrp');
    ok(scalar @results > 0, 'Found results for fuzzy "wrp"');
    # Word Wrap should match w-r-p subsequence
    my @wraps = grep { $_->{id} eq 'toggle_word_wrap' } @results;
    ok(scalar @wraps > 0, 'Word Wrap matched fuzzy "wrp"');
};

subtest 'filter_commands - empty query returns all' => sub {
    my @all = Zepto::CommandRegistry->all_commands();
    my @results = Zepto::CommandRegistry->filter_commands('');
    is(scalar @results, scalar @all, 'Empty query returns all commands');
};

subtest 'filter_commands - no match returns empty' => sub {
    my @results = Zepto::CommandRegistry->filter_commands('xyzxyzxyz');
    is(scalar @results, 0, 'Nonsense query returns empty');
};

subtest 'filter_commands - case insensitive' => sub {
    my @lower = Zepto::CommandRegistry->filter_commands('save');
    my @upper = Zepto::CommandRegistry->filter_commands('SAVE');
    ok(scalar @lower > 0, 'Lowercase matches');
    ok(scalar @upper > 0, 'Uppercase matches');
};

subtest 'commands_for_status_bar respects priority' => sub {
    my @pills = Zepto::CommandRegistry->commands_for_status_bar(
        'document', 120, undef);
    ok(scalar @pills > 0, 'Got status bar commands');

    # All returned commands should have priority > 0
    for my $cmd (@pills) {
        ok($cmd->{priority} > 0, "Command '$cmd->{id}' has positive priority");
    }

    # Should be sorted by priority
    for my $i (1 .. $#pills) {
        ok($pills[$i]->{priority} >= $pills[$i-1]->{priority},
           "Commands sorted by priority: $pills[$i-1]->{id} <= $pills[$i]->{id}");
    }
};

subtest 'toggle commands have correct type' => sub {
    my @toggles = grep { $_->{type} eq 'toggle' } Zepto::CommandRegistry->all_commands();
    ok(scalar @toggles >= 5, 'At least 5 toggle commands');
    for my $cmd (@toggles) {
        like($cmd->{id}, qr/toggle/, "Toggle '$cmd->{id}' has toggle in id");
    }
};

subtest 'All shortcuts are unique' => sub {
    my @cmds = Zepto::CommandRegistry->all_commands();
    my %seen;
    for my $cmd (@cmds) {
        next unless defined $cmd->{shortcut} && $cmd->{shortcut} ne '';
        ok(!$seen{$cmd->{shortcut}},
           "Shortcut '$cmd->{shortcut}' for '$cmd->{id}' is unique"
           . ($seen{$cmd->{shortcut}} ? " (conflicts with '$seen{$cmd->{shortcut}}')" : ''));
        $seen{$cmd->{shortcut}} = $cmd->{id};
    }
};

subtest 'All command sections are in SECTION_ORDER' => sub {
    my @cmds = Zepto::CommandRegistry->all_commands();
    my @order = Zepto::CommandRegistry->section_order();
    my %valid = map { $_ => 1 } @order;
    for my $cmd (@cmds) {
        ok($valid{$cmd->{section}},
           "Section '$cmd->{section}' for '$cmd->{id}' is in SECTION_ORDER");
    }
};

subtest 'New preference commands are registered and reflect toggle state' => sub {
    require Zepto::Preferences;

    for my $case (
        { id => 'toggle_soft_tabs',       pref => 'soft_tabs' },
        { id => 'toggle_auto_indent',     pref => 'auto_indent' },
        { id => 'toggle_mouse',           pref => 'mouse_enabled' },
        { id => 'toggle_search_wrap',     pref => 'search_wrap' },
        { id => 'toggle_markdown_tables', pref => 'render_markdown_tables' },
    ) {
        my $cmd = Zepto::CommandRegistry->find_command($case->{id});
        ok(defined $cmd, "Command '$case->{id}' is registered");
        is($cmd->{type}, 'toggle', "Command '$case->{id}' is a toggle");
        is($cmd->{pref}, $case->{pref}, "Command '$case->{id}' is wired to pref '$case->{pref}'");

        my $fake_editor = { prefs => Zepto::Preferences->new() };
        is(Zepto::CommandRegistry->get_toggle_state($cmd, $fake_editor), 1,
            "'$case->{id}' reports ON by default");

        $fake_editor->{prefs}->set($case->{pref}, 0);
        is(Zepto::CommandRegistry->get_toggle_state($cmd, $fake_editor), 0,
            "'$case->{id}' reports OFF after pref flips");
    }

    my $cmd = Zepto::CommandRegistry->find_command('set_tab_width');
    ok(defined $cmd, "Command 'set_tab_width' is registered");
    is($cmd->{type}, 'action', "'set_tab_width' is an action (numeric value, not boolean)");
    is($cmd->{method}, 'cmd_set_tab_width', "'set_tab_width' method name");
};

subtest 'section order is consistent' => sub {
    my @order = Zepto::CommandRegistry->section_order();
    is($order[0], 'FILE', 'First section is FILE');
    is($order[1], 'EDIT', 'Second section is EDIT');
    is($order[2], 'NAVIGATE', 'Third section is NAVIGATE');
    is($order[3], 'VIEW', 'Fourth section is VIEW');
};

done_testing();
