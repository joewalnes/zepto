#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use Zepto::Editor::TabManager;
use Zepto::Document;
use Zepto::View;
use Zepto::FindEngine;

# =============================================================================
# Helper to create a tab with a Document
# =============================================================================
sub make_doc {
    my (%opts) = @_;
    my $text = $opts{text} // '';
    my $doc = Zepto::Document->new(path => $opts{path});
    $doc->insert(0, $text) if length $text;
    $doc->mark_clean();
    return $doc;
}

sub make_tab_args {
    my (%opts) = @_;
    my $doc = $opts{document} // make_doc(
        text => ($opts{text} // ''),
        path => $opts{file_path},
    );
    my $view = Zepto::View->new(document => $doc);
    my $fe = Zepto::FindEngine->new(document => $doc);
    return (
        document    => $doc,
        view        => $view,
        find_engine => $fe,
        highlighter => undef,
        file_path   => $opts{file_path},
        untitled_name => $opts{untitled_name},
    );
}

# =============================================================================
# Basic construction and tab management
# =============================================================================
subtest 'Construction creates empty manager' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    is($tm->tab_count(), 0, 'No tabs initially');
    is($tm->active_index(), 0, 'Active index is 0');
};

subtest 'Add tab and access' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    my $idx = $tm->add_tab(make_tab_args(file_path => '/foo/bar.pl'));

    is($idx, 0, 'First tab at index 0');
    is($tm->tab_count(), 1, 'One tab');
    is($tm->active_index(), 0, 'Active is the new tab');
    is($tm->active_file_path(), '/foo/bar.pl', 'File path correct');
    ok($tm->active_doc(), 'Active doc exists');
    ok($tm->active_view(), 'Active view exists');
};

subtest 'Multiple tabs and switching' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    $tm->add_tab(make_tab_args(file_path => '/a.pl'));
    $tm->add_tab(make_tab_args(file_path => '/b.py'));
    $tm->add_tab(make_tab_args(file_path => '/c.rb'));

    is($tm->tab_count(), 3, 'Three tabs');
    is($tm->active_index(), 2, 'Active is last added');

    $tm->set_active(0);
    is($tm->active_index(), 0, 'Switched to tab 0');
    is($tm->active_file_path(), '/a.pl', 'Correct file path after switch');
};

subtest 'Remove tab adjusts indices' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    $tm->add_tab(make_tab_args(file_path => '/a.pl'));
    $tm->add_tab(make_tab_args(file_path => '/b.py'));
    $tm->add_tab(make_tab_args(file_path => '/c.rb'));
    $tm->set_active(2);

    $tm->remove_tab(0);
    is($tm->tab_count(), 2, 'Two tabs after removal');
    is($tm->active_index(), 1, 'Active index adjusted');
    is($tm->active_file_path(), '/c.rb', 'Active tab still c.rb');
};

subtest 'Remove active tab selects valid tab' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    $tm->add_tab(make_tab_args(file_path => '/a.pl'));
    $tm->add_tab(make_tab_args(file_path => '/b.py'));
    $tm->set_active(1);

    $tm->remove_tab(1);
    is($tm->tab_count(), 1, 'One tab after removal');
    is($tm->active_index(), 0, 'Active clamped to valid index');
    is($tm->active_file_path(), '/a.pl', 'Remaining tab is a.pl');
};

# =============================================================================
# MRU stack
# =============================================================================
subtest 'MRU stack tracks usage order' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    $tm->add_tab(make_tab_args(file_path => '/a.pl'));   # MRU: [0]
    $tm->add_tab(make_tab_args(file_path => '/b.py'));   # MRU: [1, 0]
    $tm->add_tab(make_tab_args(file_path => '/c.rb'));   # MRU: [2, 1, 0]

    is($tm->mru_previous(), 1, 'MRU previous is tab 1');

    $tm->set_active(0);  # MRU: [0, 2, 1]
    is($tm->mru_previous(), 2, 'After switching to 0, MRU previous is 2');
};

# =============================================================================
# Tab reordering
# =============================================================================
subtest 'Move tab left and right' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    $tm->add_tab(make_tab_args(file_path => '/a.pl'));
    $tm->add_tab(make_tab_args(file_path => '/b.py'));
    $tm->add_tab(make_tab_args(file_path => '/c.rb'));
    $tm->set_active(2);

    # Move tab 2 (c.rb) to position 0
    $tm->move_tab(2, 0);
    is($tm->active_index(), 0, 'Active follows moved tab');
    is($tm->tab_at(0)->{file_path}, '/c.rb', 'c.rb is now first');
    is($tm->tab_at(1)->{file_path}, '/a.pl', 'a.pl shifted right');
    is($tm->tab_at(2)->{file_path}, '/b.py', 'b.py at end');
};

# =============================================================================
# Find tab by path
# =============================================================================
subtest 'Find tab by path' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    $tm->add_tab(make_tab_args(file_path => '/tmp/test.pl'));
    $tm->add_tab(make_tab_args(untitled_name => '[untitled]'));

    is($tm->find_tab_by_path('/tmp/test.pl'), 0, 'Found by exact path');
    is($tm->find_tab_by_path('/nonexistent'), undef, 'Not found returns undef');
    is($tm->find_tab_by_path(undef), undef, 'Undef path returns undef');
};

# =============================================================================
# Untitled naming
# =============================================================================
subtest 'Untitled names increment' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    is($tm->next_untitled_name(), '[untitled]', 'First is [untitled]');
    is($tm->next_untitled_name(), '[untitled-2]', 'Second is [untitled-2]');
    is($tm->next_untitled_name(), '[untitled-3]', 'Third is [untitled-3]');
};

# =============================================================================
# Filename disambiguation in tabs_for_render
# =============================================================================
subtest 'Duplicate basenames get parent prefix' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    $tm->add_tab(make_tab_args(file_path => '/project/src/main.rs'));
    $tm->add_tab(make_tab_args(file_path => '/project/test/main.rs'));
    $tm->add_tab(make_tab_args(file_path => '/project/lib/utils.pm'));

    my $tabs = $tm->tabs_for_render();
    is(scalar @$tabs, 3, 'Three tabs in render output');

    # Duplicate basenames should get parent directory prefix
    is($tabs->[0]{display_name}, 'src/main.rs', 'First main.rs disambiguated with src/');
    is($tabs->[1]{display_name}, 'test/main.rs', 'Second main.rs disambiguated with test/');

    # Unique basename stays as-is
    is($tabs->[2]{display_name}, 'utils.pm', 'Unique name unchanged');
};

subtest 'Untitled tabs not disambiguated' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    $tm->add_tab(make_tab_args(untitled_name => '[untitled]'));
    $tm->add_tab(make_tab_args(untitled_name => '[untitled-2]'));

    my $tabs = $tm->tabs_for_render();
    is($tabs->[0]{display_name}, '[untitled]', 'First untitled unchanged');
    is($tabs->[1]{display_name}, '[untitled-2]', 'Second untitled unchanged');
};

# =============================================================================
# Tab scroll offset
# =============================================================================
subtest 'Scroll offset get/set' => sub {
    my $tm = Zepto::Editor::TabManager->new();
    is($tm->tab_scroll_offset(), 0, 'Default scroll offset is 0');
    $tm->set_tab_scroll_offset(3);
    is($tm->tab_scroll_offset(), 3, 'Scroll offset updated');
};

# =============================================================================
# Renderer tab overflow helpers
# =============================================================================
subtest 'Tab pill width calculation' => sub {
    # Test the Renderer's _calc_tab_pill_width function
    require Zepto::Renderer;

    # Width = left_tri(1) + " name" + " ×"(2) + right_tri(1) + gap(1) = 6 + name_len
    # For tab 0 (has hint): + 3 (space + ⌥N)
    my $w = Zepto::Renderer::_calc_tab_pill_width('foo.pl', 0, 0);
    is($w, 6 + 6 + 3, 'Clean tab 0 width: base(6) + name(6) + hint(3)');

    # Dirty tab: + 2
    my $w_dirty = Zepto::Renderer::_calc_tab_pill_width('foo.pl', 1, 0);
    is($w_dirty, $w + 2, 'Dirty adds 2 to width');

    # Tab index >= 9: no hint
    my $w_no_hint = Zepto::Renderer::_calc_tab_pill_width('foo.pl', 0, 9);
    is($w_no_hint, $w - 3, 'Tab 9+ has no hint (-3)');
};

subtest 'Name truncation preserves extension' => sub {
    my @info = (
        { orig_name => 'very_long_filename.pl', name => 'very_long_filename.pl',
          is_dirty => 0, index => 0, width => 0 },
        { orig_name => 'short.py', name => 'short.py',
          is_dirty => 0, index => 1, width => 0 },
    );
    # Calculate widths
    for my $t (@info) {
        $t->{width} = Zepto::Renderer::_calc_tab_pill_width($t->{name}, $t->{is_dirty}, $t->{index});
    }

    my $total_before = 0;
    $total_before += $_->{width} for @info;

    # Force truncation by giving a very tight budget
    Zepto::Renderer::_truncate_tab_names(\@info, 40);

    # The longer name should be truncated
    ok(length($info[0]{name}) < length($info[0]{orig_name}), 'Long name was truncated');
    like($info[0]{name}, qr/\.pl$/, 'Extension preserved after truncation');
    like($info[0]{name}, qr/\x{2026}/, 'Ellipsis present in truncated name');

    # The shorter name may or may not be truncated depending on budget
    ok(length($info[1]{name}) <= length($info[1]{orig_name}), 'Short name not longer than original');
};

done_testing();
