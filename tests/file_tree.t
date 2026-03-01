#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec;

use lib 'lib';
use Zepto::FileTree;

# =============================================================================
# Test Setup - Create temporary directory structure
# =============================================================================

my $tmpdir = tempdir(CLEANUP => 1);

# Create test file structure:
#   lib/
#     Editor/
#       Commands.pm
#       Palette.pm
#     Document.pm
#     Editor.pm
#   src/
#     utils/
#       helpers/
#         format.js     (deep nesting for single-child collapse test)
#     main.rs
#   tests/
#     document.t
#     editor.t
#   .gitignore
#   README.md

my @test_files = (
    'lib/Editor/Commands.pm',
    'lib/Editor/Palette.pm',
    'lib/Document.pm',
    'lib/Editor.pm',
    'src/utils/helpers/format.js',
    'src/main.rs',
    'tests/document.t',
    'tests/editor.t',
    '.gitignore',
    'README.md',
);

for my $file (@test_files) {
    my $path = "$tmpdir/$file";
    my ($dir) = $path =~ m{(.+)/[^/]+$};
    make_path($dir) if $dir && !-d $dir;
    open my $fh, '>', $path or die "Can't create $path: $!";
    print $fh "test content for $file\n";
    close $fh;
}

# Create a directory that should be skipped
make_path("$tmpdir/.git/objects");
open my $fh, '>', "$tmpdir/.git/objects/test" or die $!;
close $fh;

# Also create node_modules to test skip
make_path("$tmpdir/node_modules/foo");
open $fh, '>', "$tmpdir/node_modules/foo/bar.js" or die $!;
close $fh;

# =============================================================================
# Construction
# =============================================================================

subtest 'Construction' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);
    isa_ok($tree, 'Zepto::FileTree');

    is($tree->root_path(), $tmpdir, 'root_path set correctly');
    is($tree->panel_width(), 23, 'default panel width');
    is($tree->focused(), 0, 'not focused by default');
    is($tree->filter_active(), 0, 'filter not active by default');
    ok($tree->visible_count() > 0, 'flat_list has entries');
};

# =============================================================================
# Tree Structure
# =============================================================================

subtest 'Tree structure - dirs first, alpha sorted' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);
    my $flat = $tree->flat_list();

    # Top-level: dirs first (lib, src, tests), then files (.gitignore, README.md)
    # All dirs collapsed by default, so only top-level visible
    my @names = map { $_->{name} } @$flat;

    # Dirs should come first
    my @dirs = grep { $_->{is_dir} } @$flat;
    my @files = grep { !$_->{is_dir} } @$flat;

    # Verify dirs appear before files in the list
    my $last_dir_idx = 0;
    my $first_file_idx = scalar(@$flat);
    for my $i (0 .. $#$flat) {
        $last_dir_idx = $i if $flat->[$i]{is_dir};
        $first_file_idx = $i if !$flat->[$i]{is_dir} && $i < $first_file_idx;
    }
    ok($last_dir_idx < $first_file_idx, 'dirs come before files');

    # Should have 3 dirs (lib, src, tests) and 2 files (.gitignore, README.md)
    is(scalar @dirs, 3, '3 top-level dirs');
    is(scalar @files, 2, '2 top-level files');
};

subtest 'Skip directories' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);
    my $flat = $tree->flat_list();

    # .git and node_modules should not appear
    my @names = map { $_->{name} } @$flat;
    ok(!(grep { $_ eq '.git' } @names), '.git not in tree');
    ok(!(grep { $_ eq 'node_modules' } @names), 'node_modules not in tree');
};

# =============================================================================
# Single-child Directory Collapsing
# =============================================================================

subtest 'Single-child directory collapsing' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);
    my $flat = $tree->flat_list();

    # src/ has two children: utils/ and main.rs
    # So src/ should NOT be collapsed with utils/
    # But utils/ has only one child (helpers/) which has only one child (format.js)
    # So after collapsing: utils/helpers should appear as one node

    # First, find and expand src/
    my ($src_idx) = grep { $flat->[$_]{name} eq 'src' } 0 .. $#$flat;
    ok(defined $src_idx, 'found src/ in tree');

    # Expand src/
    $tree->set_cursor($src_idx);
    $tree->expand_current();
    $flat = $tree->flat_list();

    # Under src/, look for the collapsed utils/helpers
    my @src_children;
    for my $i (0 .. $#$flat) {
        next unless $flat->[$i]{depth} == 1;  # direct children of src/
        # Check if parent is src
        my $node = $flat->[$i];
        if ($node->{path} =~ m{^src/}) {
            push @src_children, $node;
        }
    }

    # Should find collapsed "utils/helpers" dir and "main.rs" file
    my @child_names = map { $_->{name} } @src_children;
    ok((grep { $_ eq 'utils/helpers' } @child_names), 'single-child dirs collapsed into utils/helpers');
    ok((grep { $_ eq 'main.rs' } @child_names), 'main.rs visible under src/');
};

# =============================================================================
# Navigation
# =============================================================================

subtest 'Navigation - move_up/move_down' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    is($tree->cursor(), 0, 'cursor starts at 0');

    $tree->move_down();
    is($tree->cursor(), 1, 'move_down increments cursor');

    $tree->move_down();
    is($tree->cursor(), 2, 'move_down again');

    $tree->move_up();
    is($tree->cursor(), 1, 'move_up decrements cursor');

    # move_up at top should stay at 0
    $tree->move_up();
    $tree->move_up();
    is($tree->cursor(), 0, 'move_up clamps at 0');

    # move_down past end should clamp
    my $max = $tree->visible_count() - 1;
    for (1 .. $max + 5) {
        $tree->move_down();
    }
    is($tree->cursor(), $max, 'move_down clamps at max');
};

subtest 'Navigation - home/end' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    $tree->move_down();
    $tree->move_down();
    $tree->home();
    is($tree->cursor(), 0, 'home moves to 0');

    $tree->end();
    is($tree->cursor(), $tree->visible_count() - 1, 'end moves to last');
};

subtest 'Navigation - page_up/page_down' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir, viewport_height => 3);

    $tree->page_down(3);
    ok($tree->cursor() > 0, 'page_down moves cursor');

    my $pos = $tree->cursor();
    $tree->page_up(3);
    is($tree->cursor(), 0, 'page_up moves cursor back');
};

# =============================================================================
# Expand / Collapse
# =============================================================================

subtest 'Expand and collapse' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);
    my $initial_count = $tree->visible_count();

    # First item should be a dir (lib/)
    my $node = $tree->cursor_node();
    ok($node->{is_dir}, 'first node is a directory');

    # Expand it
    $tree->expand_current();
    ok($tree->visible_count() > $initial_count, 'expanding dir adds children to flat list');

    # Collapse it
    $tree->collapse_current();
    is($tree->visible_count(), $initial_count, 'collapsing dir restores count');
};

subtest 'Toggle current' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);
    my $initial = $tree->visible_count();

    # Toggle dir to expand
    $tree->toggle_current();
    ok($tree->visible_count() > $initial, 'toggle expands collapsed dir');

    # Toggle again to collapse
    $tree->toggle_current();
    is($tree->visible_count(), $initial, 'toggle collapses expanded dir');
};

subtest 'Collapse on file goes to parent' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    # Expand lib/
    $tree->expand_current();

    # Move to a child (should be a file or subdir under lib/)
    $tree->move_down();
    my $child = $tree->cursor_node();
    my $child_depth = $child->{depth};

    # Collapse from child should go to parent
    if (!$child->{is_dir} || !$child->{expanded}) {
        $tree->collapse_current();
        my $after = $tree->cursor_node();
        ok($after->{is_dir}, 'collapse on file/collapsed moved to parent dir');
        ok($after->{depth} < $child_depth, 'parent has lower depth');
    }
};

# =============================================================================
# expand_to_path
# =============================================================================

subtest 'expand_to_path' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    # Expand to a deep file
    my $result = $tree->expand_to_path('lib/Editor/Commands.pm');
    ok($result, 'expand_to_path returns true for existing file');

    # Cursor should be on the target file
    my $node = $tree->cursor_node();
    is($node->{path}, 'lib/Editor/Commands.pm', 'cursor on target file');

    # Ancestor dirs should be expanded
    my $flat = $tree->flat_list();
    my ($lib_node) = grep { $_->{path} eq 'lib' } @$flat;
    ok($lib_node && $lib_node->{expanded}, 'lib/ is expanded');
};

subtest 'expand_to_path with absolute path' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    my $abs = "$tmpdir/README.md";
    my $result = $tree->expand_to_path($abs);
    ok($result, 'expand_to_path works with absolute path');

    my $node = $tree->cursor_node();
    is($node->{path}, 'README.md', 'cursor on correct file');
};

subtest 'expand_to_path nonexistent' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);
    my $result = $tree->expand_to_path('nonexistent/file.txt');
    ok(!$result, 'expand_to_path returns false for missing file');
};

# =============================================================================
# Resize
# =============================================================================

subtest 'Resize' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    is($tree->panel_width(), 23, 'default width');

    $tree->grow(5);
    is($tree->panel_width(), 28, 'grow increases width');

    $tree->shrink(10);
    is($tree->panel_width(), 18, 'shrink decreases width');

    # Clamp to min
    $tree->shrink(100);
    is($tree->panel_width(), Zepto::FileTree::MIN_TREE_WIDTH, 'shrink clamps to min');

    # Clamp to max
    $tree->grow(200);
    is($tree->panel_width(), Zepto::FileTree::MAX_TREE_WIDTH, 'grow clamps to max');

    # set_width
    $tree->set_width(30);
    is($tree->panel_width(), 30, 'set_width works');
};

# =============================================================================
# Sticky Headers
# =============================================================================

subtest 'Sticky headers' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir, viewport_height => 5);

    # Expand the path so ancestors are in flat_list
    $tree->expand_to_path('lib/Editor/Commands.pm');

    my $flat = $tree->flat_list();

    # Scroll down so lib/ and lib/Editor/ are above viewport.
    # The top visible item (Commands.pm) is inside lib/Editor/, so both
    # lib/ and Editor/ should appear as sticky headers.
    if (@$flat > 5) {
        $tree->{scroll} = 2;  # scroll past lib/ and Editor/
        my $stickies = $tree->sticky_headers();
        ok(ref($stickies) eq 'ARRAY', 'sticky_headers returns arrayref');
        ok(scalar @$stickies > 0, 'ancestors of top-visible item become sticky headers');

        my @sticky_paths = map { $_->{path} } @$stickies;
        ok((grep { $_ eq 'lib' } @sticky_paths), 'lib/ pinned as grandparent');
        ok((grep { $_ eq 'lib/Editor' } @sticky_paths), 'lib/Editor/ pinned as parent');
    }

    # No scroll = no stickies
    $tree->home();
    $tree->{scroll} = 0;
    my $stickies = $tree->sticky_headers();
    is(scalar @$stickies, 0, 'no stickies when scroll is at top');
};

subtest 'Sticky headers track scroll position, not cursor' => sub {
    # Reproduce the exact bug: cursor on a shallow sibling while viewport
    # top shows content from a deeper expanded branch.
    #
    # Structure:
    #   alpha/
    #     deep/
    #       file1..file5.txt
    #     other/
    #       other.txt
    #   beta.txt

    my $deep_dir = tempdir(CLEANUP => 1);
    make_path("$deep_dir/alpha/deep");
    for my $i (1..5) {
        open my $fh3, '>', "$deep_dir/alpha/deep/file$i.txt" or die $!;
        close $fh3;
    }
    make_path("$deep_dir/alpha/other");
    open my $fh3, '>', "$deep_dir/alpha/other/other.txt" or die $!;
    close $fh3;
    open $fh3, '>', "$deep_dir/beta.txt" or die $!;
    close $fh3;

    my $tree = Zepto::FileTree->new(root_path => $deep_dir, viewport_height => 5);

    # Expand both branches so the full flat list is visible
    $tree->expand_to_path('alpha/deep/file1.txt');
    $tree->expand_to_path('alpha/other/other.txt');

    my $flat = $tree->flat_list();

    # Find indices
    my ($file4_idx) = grep { $flat->[$_]{path} eq 'alpha/deep/file4.txt' } 0..$#$flat;
    my ($other_idx) = grep { $flat->[$_]{path} eq 'alpha/other' } 0..$#$flat;

    ok(defined $file4_idx, 'found file4.txt in flat list');
    ok(defined $other_idx, 'found alpha/other/ in flat list');

    if (defined $file4_idx && defined $other_idx) {
        # Scroll so file4.txt is at top, but put cursor on other/ (different branch)
        $tree->{scroll} = $file4_idx;
        $tree->set_cursor($other_idx);

        my $stickies = $tree->sticky_headers();
        my @sticky_paths = map { $_->{path} } @$stickies;

        # file4.txt is inside alpha/deep/, so both alpha/ and alpha/deep/
        # must appear as sticky headers — regardless of where the cursor is
        is(scalar @$stickies, 2, 'two sticky levels for deeply nested top-visible item');
        ok((grep { $_ eq 'alpha' } @sticky_paths), 'alpha/ pinned as grandparent');
        ok((grep { $_ eq 'alpha/deep' } @sticky_paths), 'alpha/deep/ pinned as parent of top-visible');
    }
};

# =============================================================================
# Scrollbar Data
# =============================================================================

subtest 'Scrollbar data' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir, viewport_height => 3);

    my $sb = $tree->scrollbar_data();
    is(ref($sb), 'HASH', 'scrollbar_data returns hashref');
    ok(exists $sb->{total}, 'has total');
    ok(exists $sb->{visible}, 'has visible');
    ok(exists $sb->{thumb_start}, 'has thumb_start');
    ok(exists $sb->{thumb_end}, 'has thumb_end');

    # With more items than viewport, thumb should be smaller than track
    if ($sb->{total} > $sb->{visible}) {
        ok($sb->{thumb_end} < $sb->{visible}, 'thumb fits within visible');
    }
};

# =============================================================================
# Fuzzy Filter
# =============================================================================

subtest 'Fuzzy filter' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    $tree->start_filter();
    ok($tree->filter_active(), 'filter is active after start');
    is($tree->filter_query(), '', 'filter query starts empty');

    # Type a query
    $tree->filter_append_char('e');
    $tree->filter_append_char('d');
    is($tree->filter_query(), 'ed', 'filter query accumulates');

    # Should have filtered results — "Editor" matches
    my $flat = $tree->flat_list();
    ok(scalar(@$flat) > 0, 'filter has results');

    # All visible files should match the query
    for my $node (@$flat) {
        next if $node->{is_dir};  # dirs are ancestors
        ok($node->{path} =~ /e.*d/i, "file $node->{path} matches filter 'ed'");
    }

    # Backspace
    $tree->filter_backspace();
    is($tree->filter_query(), 'e', 'backspace removes last char');

    # Clear filter
    $tree->clear_filter();
    ok(!$tree->filter_active(), 'filter deactivated after clear');
    is($tree->filter_query(), '', 'query cleared');
};

subtest 'Filter produces flat ranked results' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    $tree->start_filter();
    $tree->filter_append_char('C');
    $tree->filter_append_char('o');
    $tree->filter_append_char('m');

    my $flat = $tree->flat_list();

    # Should have flat file results only (no directory nodes)
    my @files = grep { !$_->{is_dir} } @$flat;
    my @dirs = grep { $_->{is_dir} } @$flat;

    ok(scalar(@files) > 0, 'matching files present');
    if (scalar(@files) > 0) {
        ok((grep { $_->{path} =~ /Commands/ } @files), 'Commands.pm matches');
        # In flat mode, name == path (full relative path shown)
        my ($cmd) = grep { $_->{path} =~ /Commands/ } @files;
        is($cmd->{name}, $cmd->{path}, 'flat mode: name equals full path');
        is($cmd->{depth}, 0, 'flat mode: depth is 0');
        ok(defined $cmd->{_filter_match_positions}, 'match positions set');
    }
    is(scalar(@dirs), 0, 'no directory nodes in flat filter results');
    is($tree->filter_match_count(), scalar(@files), 'filter_match_count matches');

    # Clear filter restores tree hierarchy
    $tree->clear_filter();
    ok(!$tree->filter_active(), 'filter cleared');
    my @restored_dirs = grep { $_->{is_dir} } @{$tree->flat_list()};
    ok(scalar(@restored_dirs) > 0, 'tree hierarchy restored after clear');
};

# =============================================================================
# VCS Status Propagation
# =============================================================================

subtest 'VCS status propagation' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    # Manually set VCS statuses
    $tree->{_vcs_statuses} = {
        'lib/Editor.pm' => 'modified',
        'README.md' => 'untracked',
    };
    $tree->_apply_vcs_statuses($tree->nodes());
    $tree->_propagate_dir_status($tree->nodes());

    # lib/ should inherit 'modified' (worst child status)
    my ($lib_node) = grep { $_->{path} eq 'lib' && $_->{is_dir} } @{$tree->flat_list()};
    ok(defined $lib_node, 'found lib/ node');
    is($lib_node->{vcs_status}, 'modified', 'dir inherits worst child status');
};

# =============================================================================
# Refresh
# =============================================================================

subtest 'Refresh preserves expand state' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    # Expand lib/
    $tree->expand_current();
    my $expanded_count = $tree->visible_count();

    # Refresh
    $tree->refresh();
    is($tree->visible_count(), $expanded_count, 'refresh preserves expand state');
};

subtest 'Refresh picks up new files in tree' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    # Expand lib/ so its children are loaded
    $tree->expand_current();
    my $flat_before = $tree->flat_list();
    my @files_before = grep { !$_->{is_dir} && $_->{path} =~ m{^lib/} } @$flat_before;

    # Add a new file to lib/ from "outside the editor"
    my $new_file = "$tmpdir/lib/NewModule.pm";
    open my $fh2, '>', $new_file or die "Can't create $new_file: $!";
    print $fh2 "package NewModule;\n1;\n";
    close $fh2;

    # Before refresh, new file should NOT appear
    my @files_still = grep { $_->{path} eq 'lib/NewModule.pm' } @{$tree->flat_list()};
    is(scalar @files_still, 0, 'new file not visible before refresh');

    # After refresh, new file SHOULD appear
    $tree->refresh();
    $tree->expand_to_path('lib/NewModule.pm');
    my @files_after = grep { $_->{path} eq 'lib/NewModule.pm' } @{$tree->flat_list()};
    is(scalar @files_after, 1, 'new file visible after refresh');

    # Clean up
    unlink $new_file;
    $tree->refresh();
};

subtest 'Filter rescans filesystem on each activation' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    # Prime the filter — BrandNew doesn't exist yet
    $tree->start_filter();
    $tree->filter_append_char('B');
    $tree->filter_append_char('r');
    $tree->filter_append_char('a');
    $tree->filter_append_char('n');
    $tree->filter_append_char('d');
    my @before = grep { $_->{path} =~ /BrandNew/ } @{$tree->flat_list()};
    is(scalar @before, 0, 'BrandNew not in filter results before creation');
    $tree->clear_filter();

    # Add a new file from outside the editor (e.g. git pull)
    my $new_file = "$tmpdir/BrandNew.txt";
    open my $fh2, '>', $new_file or die "Can't create $new_file: $!";
    print $fh2 "brand new content\n";
    close $fh2;

    # start_filter() rescans the filesystem each time, so the new file
    # should appear without needing an explicit refresh() call.
    # This is the Ctrl+O code path.
    $tree->start_filter();
    $tree->filter_append_char('B');
    $tree->filter_append_char('r');
    $tree->filter_append_char('a');
    $tree->filter_append_char('n');
    $tree->filter_append_char('d');
    my @after = grep { $_->{path} =~ /BrandNew/ } @{$tree->flat_list()};
    is(scalar @after, 1, 'new file appears in filter on next activation');

    # Clean up
    $tree->clear_filter();
    unlink $new_file;
    $tree->refresh();
};

# =============================================================================
# Accessors
# =============================================================================

subtest 'Accessors' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir);

    $tree->set_focused(1);
    is($tree->focused(), 1, 'set_focused/focused');

    $tree->set_focused(0);
    is($tree->focused(), 0, 'unfocused');

    $tree->set_current_file('lib/Editor.pm');
    is($tree->current_file(), 'lib/Editor.pm', 'set/get current_file');

    # Absolute path gets converted to relative
    $tree->set_current_file("$tmpdir/README.md");
    is($tree->current_file(), 'README.md', 'absolute path converted to relative');

    $tree->set_viewport_height(30);
    is($tree->viewport_height(), 30, 'set/get viewport_height');
};

# =============================================================================
# Scroll behavior
# =============================================================================

subtest 'Scroll ensures visibility' => sub {
    my $tree = Zepto::FileTree->new(root_path => $tmpdir, viewport_height => 2);

    # With small viewport, scrolling should kick in
    $tree->move_down();
    $tree->move_down();
    $tree->move_down();

    ok($tree->scroll() > 0, 'scroll advances when cursor passes viewport');

    $tree->home();
    is($tree->scroll(), 0, 'home resets scroll to 0');
};

done_testing();
