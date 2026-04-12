#!/usr/bin/env perl
# Tests for Zepto::Preferences
use strict;
use warnings;
use Test::More;
use File::Temp;
use lib 'lib';
use Zepto::Preferences;
use Zepto::StateStore;

# ============================================================================
# Construction
# ============================================================================
subtest 'Construction' => sub {
    my $prefs = Zepto::Preferences->new();
    ok($prefs, 'Preferences created');
};

subtest 'Construction with initial values' => sub {
    my $prefs = Zepto::Preferences->new(
        theme => 'light',
        tab_width => 2,
    );
    is($prefs->get('theme'), 'light', 'Initial theme');
    is($prefs->get('tab_width'), 2, 'Initial tab_width');
};

# ============================================================================
# Default values
# ============================================================================
subtest 'Default values' => sub {
    my $prefs = Zepto::Preferences->new();

    is($prefs->get('theme'), 'dark', 'Default theme');
    is($prefs->get('tab_width'), 4, 'Default tab_width');
    is($prefs->get('soft_tabs'), 1, 'Default soft_tabs');
    is($prefs->get('auto_indent'), 1, 'Default auto_indent');
    is($prefs->get('show_line_numbers'), 1, 'Default show_line_numbers');
    is($prefs->get('show_status_bar'), 1, 'Default show_status_bar');
    is($prefs->get('search_case_sensitive'), 0, 'Default search_case_sensitive');
    is($prefs->get('search_regex'), 0, 'Default search_regex');
    is($prefs->get('search_wrap'), 1, 'Default search_wrap');
    is($prefs->get('mouse_enabled'), 1, 'Default mouse_enabled');
    is($prefs->get('scroll_margin'), 3, 'Default scroll_margin');
};

# ============================================================================
# Get/Set
# ============================================================================
subtest 'Get and set' => sub {
    my $prefs = Zepto::Preferences->new();

    $prefs->set('theme', 'light');
    is($prefs->get('theme'), 'light', 'Set and get');

    $prefs->set('tab_width', 8);
    is($prefs->get('tab_width'), 8, 'Numeric value');

    $prefs->set('soft_tabs', 0);
    is($prefs->get('soft_tabs'), 0, 'Boolean value');
};

subtest 'Get unknown key' => sub {
    my $prefs = Zepto::Preferences->new();
    is($prefs->get('nonexistent'), undef, 'Unknown key returns undef');
};

subtest 'Set unknown key' => sub {
    my $prefs = Zepto::Preferences->new();
    $prefs->set('custom_key', 'custom_value');
    is($prefs->get('custom_key'), 'custom_value', 'Custom key works');
};

# ============================================================================
# Reset
# ============================================================================
subtest 'Reset single preference' => sub {
    my $prefs = Zepto::Preferences->new();
    $prefs->set('theme', 'light');
    $prefs->set('tab_width', 8);

    $prefs->reset('theme');
    is($prefs->get('theme'), 'dark', 'Theme reset to default');
    is($prefs->get('tab_width'), 8, 'Other prefs unchanged');
};

subtest 'Reset all preferences' => sub {
    my $prefs = Zepto::Preferences->new();
    $prefs->set('theme', 'light');
    $prefs->set('tab_width', 8);
    $prefs->set('soft_tabs', 0);

    $prefs->reset_all();
    is($prefs->get('theme'), 'dark', 'Theme reset');
    is($prefs->get('tab_width'), 4, 'Tab width reset');
    is($prefs->get('soft_tabs'), 1, 'Soft tabs reset');
};

subtest 'Get default value' => sub {
    my $prefs = Zepto::Preferences->new();
    $prefs->set('tab_width', 8);

    is($prefs->default('tab_width'), 4, 'Default unchanged');
    is($prefs->get('tab_width'), 8, 'Current value different');
};

# ============================================================================
# All/exists/keys
# ============================================================================
subtest 'All preferences' => sub {
    my $prefs = Zepto::Preferences->new();
    my %all = $prefs->all();

    ok(exists $all{theme}, 'All has theme');
    ok(exists $all{tab_width}, 'All has tab_width');
    ok(scalar(keys %all) > 10, 'Many preferences');
};

subtest 'Exists' => sub {
    my $prefs = Zepto::Preferences->new();
    ok($prefs->exists('theme'), 'Theme exists');
    ok(!$prefs->exists('nonexistent'), 'Nonexistent does not exist');
};

subtest 'Keys' => sub {
    my $prefs = Zepto::Preferences->new();
    my @keys = $prefs->keys();

    ok(scalar(@keys) > 10, 'Many keys');
    ok(grep({ $_ eq 'theme' } @keys), 'Theme in keys');
    ok(grep({ $_ eq 'tab_width' } @keys), 'Tab width in keys');
};

# ============================================================================
# Change notification
# ============================================================================
subtest 'Change callback' => sub {
    my $prefs = Zepto::Preferences->new();
    my @changes;

    my $id = $prefs->on_change(sub {
        my ($key, $new, $old) = @_;
        push @changes, { key => $key, new => $new, old => $old };
    });

    ok($id, 'Callback registered');

    $prefs->set('theme', 'light');
    is(scalar @changes, 1, 'One change');
    is($changes[0]->{key}, 'theme', 'Change key');
    is($changes[0]->{new}, 'light', 'New value');
    is($changes[0]->{old}, 'dark', 'Old value');
};

subtest 'Multiple callbacks' => sub {
    my $prefs = Zepto::Preferences->new();
    my ($called1, $called2) = (0, 0);

    $prefs->on_change(sub { $called1++ });
    $prefs->on_change(sub { $called2++ });

    $prefs->set('theme', 'light');
    is($called1, 1, 'First callback called');
    is($called2, 1, 'Second callback called');
};

subtest 'Remove callback' => sub {
    my $prefs = Zepto::Preferences->new();
    my $called = 0;

    my $id = $prefs->on_change(sub { $called++ });
    $prefs->set('theme', 'light');
    is($called, 1, 'Callback called once');

    $prefs->off_change($id);
    $prefs->set('theme', 'dark');
    is($called, 1, 'Callback not called after removal');
};

subtest 'No callback for unchanged value' => sub {
    my $prefs = Zepto::Preferences->new();
    my $called = 0;

    $prefs->on_change(sub { $called++ });

    $prefs->set('theme', 'dark');  # Already dark
    is($called, 0, 'No callback for unchanged value');
};

# ============================================================================
# Convenience accessors
# ============================================================================
subtest 'Theme accessor' => sub {
    my $prefs = Zepto::Preferences->new();
    is($prefs->theme(), 'dark', 'Theme getter');

    $prefs->set_theme('light');
    is($prefs->theme(), 'light', 'Theme setter');
};

subtest 'Tab width accessor' => sub {
    my $prefs = Zepto::Preferences->new();
    is($prefs->tab_width(), 4, 'Tab width getter');

    $prefs->set_tab_width(2);
    is($prefs->tab_width(), 2, 'Tab width setter');
};

subtest 'Soft tabs accessor' => sub {
    my $prefs = Zepto::Preferences->new();
    is($prefs->soft_tabs(), 1, 'Soft tabs getter');

    $prefs->set_soft_tabs(0);
    is($prefs->soft_tabs(), 0, 'Soft tabs setter');
};

subtest 'Other accessors' => sub {
    my $prefs = Zepto::Preferences->new();

    ok($prefs->auto_indent(), 'Auto indent getter');
    ok($prefs->show_line_numbers(), 'Show line numbers getter');
    ok($prefs->mouse_enabled(), 'Mouse enabled getter');
    ok(!$prefs->search_case_sensitive(), 'Search case sensitive getter');
    ok($prefs->search_wrap(), 'Search wrap getter');
};

# ============================================================================
# Tab/space conversion
# ============================================================================
subtest 'Tab string with soft tabs' => sub {
    my $prefs = Zepto::Preferences->new(soft_tabs => 1, tab_width => 4);
    is($prefs->tab_string(), '    ', 'Four spaces');

    $prefs->set_tab_width(2);
    is($prefs->tab_string(), '  ', 'Two spaces');
};

subtest 'Tab string with hard tabs' => sub {
    my $prefs = Zepto::Preferences->new(soft_tabs => 0);
    is($prefs->tab_string(), "\t", 'Tab character');
};

subtest 'Expand tabs' => sub {
    my $prefs = Zepto::Preferences->new(tab_width => 4);
    is($prefs->expand_tabs("\thello"), '    hello', 'Tab at start');
    is($prefs->expand_tabs("a\tb"), 'a    b', 'Tab in middle');
    is($prefs->expand_tabs("\t\t"), '        ', 'Multiple tabs');
    is($prefs->expand_tabs("no tabs"), 'no tabs', 'No tabs');
    is($prefs->expand_tabs(undef), undef, 'Undef returns undef');
};

subtest 'Visual width' => sub {
    my $prefs = Zepto::Preferences->new(tab_width => 4);

    is($prefs->visual_width('hello'), 5, 'Plain string');
    is($prefs->visual_width("\thello"), 9, 'Tab at start: 4 + 5');
    # "ab" is 2 chars, tab goes to col 4, then "c" -> 4 + 1 = 5
    is($prefs->visual_width("ab\tc"), 5, 'Tab with offset 2 -> 4, then c');
    # "abc" is 3 chars, tab goes to col 4, then "d" -> 4 + 1 = 5
    is($prefs->visual_width("abc\td"), 5, 'Tab with offset 3 -> 4, then d');
    # "abcd" is 4 chars, tab goes to col 8, then "e" -> 8 + 1 = 9
    is($prefs->visual_width("abcd\te"), 9, 'Tab with offset 4 -> 8, then e');
    is($prefs->visual_width(''), 0, 'Empty string');
    is($prefs->visual_width(undef), 0, 'Undef returns 0');
};

# ============================================================================
# Persistence via StateStore
# ============================================================================
subtest 'Persistence: global prefs are saved to StateStore' => sub {
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);
    my $prefs = Zepto::Preferences->new(state_store => $store);

    $prefs->set_theme('light');
    my $data = $store->get('preferences');
    is($data->{theme}, 'light', 'Theme persisted to StateStore');
};

subtest 'Persistence: prefs load from StateStore on init' => sub {
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);

    # Save some prefs
    $store->put('preferences', { theme => 'light', tab_width => 2 });

    # Create new Preferences instance — should load persisted values
    my $prefs = Zepto::Preferences->new(state_store => $store);
    is($prefs->get('theme'), 'light', 'Theme loaded from store');
    is($prefs->get('tab_width'), 2, 'Tab width loaded from store');
    # Non-persisted should still be default
    is($prefs->get('scroll_margin'), 3, 'Non-persisted pref is default');
};

subtest 'Persistence: round-trip via StateStore' => sub {
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $tmpdir);

    my $prefs1 = Zepto::Preferences->new(state_store => $store);
    $prefs1->set_theme('light');
    $prefs1->set_tab_width(2);
    $prefs1->set_nerd_font(0);

    # New instance loads the same values
    my $prefs2 = Zepto::Preferences->new(state_store => $store);
    is($prefs2->get('theme'), 'light', 'Theme round-trip');
    is($prefs2->get('tab_width'), 2, 'Tab width round-trip');
    is($prefs2->get('nerd_font'), 0, 'Nerd font round-trip');
};

subtest 'Persistence: cross-instance sync via on_change' => sub {
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $store_a = Zepto::StateStore->new(base_dir => $tmpdir);
    my $store_b = Zepto::StateStore->new(base_dir => $tmpdir);

    my $prefs_a = Zepto::Preferences->new(state_store => $store_a);
    my $prefs_b = Zepto::Preferences->new(state_store => $store_b);

    # Instance A changes theme
    $prefs_a->set_theme('light');
    sleep 1;  # Ensure mtime differs

    # Instance B picks up the change
    $store_b->check_for_changes();
    is($prefs_b->get('theme'), 'light', 'Cross-instance theme sync');
};

# ============================================================================
# Filetype word wrap defaults
# ============================================================================
subtest 'should_default_wrap for prose filetypes' => sub {
    my $prefs = Zepto::Preferences->new();

    # Extensions that should default to wrap
    ok($prefs->should_default_wrap('README.md'), 'Markdown files wrap');
    ok($prefs->should_default_wrap('notes.txt'), 'Text files wrap');
    ok($prefs->should_default_wrap('doc.rst'), 'RST files wrap');
    ok($prefs->should_default_wrap('guide.adoc'), 'AsciiDoc files wrap');
    ok($prefs->should_default_wrap('README.markdown'), 'Long markdown ext wraps');
    ok($prefs->should_default_wrap('file.text'), 'Long text ext wraps');

    # Case insensitive
    ok($prefs->should_default_wrap('NOTES.TXT'), 'Case insensitive extension');
    ok($prefs->should_default_wrap('readme.MD'), 'Mixed case extension');
};

subtest 'should_default_wrap for code filetypes' => sub {
    my $prefs = Zepto::Preferences->new();

    # Code files should not default to wrap
    ok(!$prefs->should_default_wrap('main.py'), 'Python files do not wrap');
    ok(!$prefs->should_default_wrap('app.js'), 'JavaScript files do not wrap');
    ok(!$prefs->should_default_wrap('lib.rs'), 'Rust files do not wrap');
    ok(!$prefs->should_default_wrap('Main.java'), 'Java files do not wrap');
    ok(!$prefs->should_default_wrap('editor.pm'), 'Perl files do not wrap');
    ok(!$prefs->should_default_wrap('Makefile'), 'No extension does not wrap');
};

subtest 'should_default_wrap edge cases' => sub {
    my $prefs = Zepto::Preferences->new();

    ok(!$prefs->should_default_wrap(undef), 'Undef filename does not wrap');
    ok(!$prefs->should_default_wrap(''), 'Empty filename does not wrap');
    ok($prefs->should_default_wrap('/path/to/README.md'), 'Full path with md wraps');
    ok($prefs->should_default_wrap('some.file.txt'), 'Multi-dot filename wraps on last ext');
};

done_testing();
