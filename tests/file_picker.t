#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

use lib 'lib';
use Zepto::FilePicker;
use Zepto::Config;

# =============================================================================
# Test Setup - Create temporary directory structure
# =============================================================================

my $tmpdir = tempdir(CLEANUP => 1);

# Create test file structure
my @test_files = (
    'README.md',
    'lib/Editor.pm',
    'lib/Editor/Commands.pm',
    'lib/Editor/Menu.pm',
    'lib/Document.pm',
    'tests/editor.t',
    'tests/document.t',
    '.gitignore',
    'src/main.rs',
);

for my $file (@test_files) {
    my $path = "$tmpdir/$file";
    my ($dir) = $path =~ m{(.+)/[^/]+$};
    make_path($dir) if $dir && !-d $dir;
    open my $fh, '>', $path or die "Can't create $path: $!";
    print $fh "test content\n";
    close $fh;
}

# Create a directory that should be skipped
make_path("$tmpdir/.git/objects");
open my $fh, '>', "$tmpdir/.git/objects/test" or die $!;
close $fh;

# =============================================================================
# Construction
# =============================================================================

subtest 'Construction' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);
    ok($picker, 'FilePicker created');
    is($picker->query(), '', 'Query initially empty');
    ok($picker->total_files() > 0, 'Files discovered');
    ok($picker->filtered_count() > 0, 'Filtered list populated');
};

# =============================================================================
# File Discovery
# =============================================================================

subtest 'File discovery' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    my $total = $picker->total_files();
    is($total, scalar(@test_files), 'Correct number of files discovered');

    # Check .git directory was skipped
    my @filtered = @{$picker->filtered()};
    my @git_files = grep { /\.git\/objects/ } @filtered;
    is(scalar(@git_files), 0, '.git directory skipped');

    # Check dotfiles are included
    my @dotfiles = grep { /\.gitignore/ } @filtered;
    is(scalar(@dotfiles), 1, 'Dotfiles included');
};

# =============================================================================
# Fuzzy Matching
# =============================================================================

subtest 'Fuzzy matching - basic' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    $picker->set_query('edit');
    my @filtered = @{$picker->filtered()};

    ok(scalar(@filtered) > 0, 'Matches found for "edit"');

    # All results should contain 'edit' characters in sequence
    for my $file (@filtered) {
        like(lc($file), qr/e.*d.*i.*t/i, "File '$file' matches 'edit' pattern");
    }
};

subtest 'Fuzzy matching - scoring' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    $picker->set_query('Editor');
    my @filtered = @{$picker->filtered()};

    ok(scalar(@filtered) > 0, 'Matches found');

    # Editor.pm should score higher than editor.t (exact filename match)
    my $editor_pm_idx = -1;
    my $editor_t_idx = -1;
    for my $i (0 .. $#filtered) {
        $editor_pm_idx = $i if $filtered[$i] =~ /Editor\.pm$/;
        $editor_t_idx = $i if $filtered[$i] =~ /editor\.t$/;
    }

    ok($editor_pm_idx >= 0, 'Editor.pm found');
};

subtest 'Fuzzy matching - no matches' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    $picker->set_query('xyznonexistent');
    my @filtered = @{$picker->filtered()};

    is(scalar(@filtered), 0, 'No matches for nonsense query');
};

subtest 'Fuzzy matching - empty query shows all' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    $picker->set_query('');
    is($picker->filtered_count(), $picker->total_files(), 'Empty query shows all files');
};

# =============================================================================
# Query Manipulation
# =============================================================================

subtest 'Query manipulation' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    $picker->append_char('e');
    is($picker->query(), 'e', 'Char appended');

    $picker->append_char('d');
    is($picker->query(), 'ed', 'Second char appended');

    $picker->backspace();
    is($picker->query(), 'e', 'Backspace removes char');

    $picker->backspace();
    is($picker->query(), '', 'Backspace on empty is no-op');

    $picker->backspace();
    is($picker->query(), '', 'Multiple backspace on empty safe');
};

# =============================================================================
# Navigation
# =============================================================================

subtest 'Navigation - up/down' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    is($picker->selected(), 0, 'Initially at index 0');

    $picker->move_down();
    is($picker->selected(), 1, 'Move down increments');

    $picker->move_up();
    is($picker->selected(), 0, 'Move up decrements');

    $picker->move_up();
    is($picker->selected(), 0, 'Move up at 0 stays at 0');
};

subtest 'Navigation - page up/down' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    # Start at 0
    is($picker->selected(), 0, 'Start at 0');

    # Page down
    $picker->page_down(3);
    is($picker->selected(), 3, 'Page down moves by visible rows');

    # Page up
    $picker->page_up(3);
    is($picker->selected(), 0, 'Page up moves back');

    # Page up at top stays at top
    $picker->page_up(3);
    is($picker->selected(), 0, 'Page up at top stays');
};

subtest 'Navigation - select_index' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    $picker->select_index(2);
    is($picker->selected(), 2, 'select_index works');

    $picker->select_index(-1);
    is($picker->selected(), 2, 'Negative index ignored');

    $picker->select_index(9999);
    is($picker->selected(), 2, 'Out of bounds index ignored');
};

# =============================================================================
# Selection
# =============================================================================

subtest 'Selection' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    my $first = $picker->selected_file();
    ok(defined $first, 'Selected file defined');
    ok(length($first) > 0, 'Selected file not empty');

    $picker->move_down();
    my $second = $picker->selected_file();
    isnt($first, $second, 'Different selection after move');
};

# =============================================================================
# Callbacks
# =============================================================================

subtest 'Callbacks' => sub {
    my $selected_file;
    my $cancelled = 0;

    my $picker = Zepto::FilePicker->new(
        base_dir => $tmpdir,
        on_select => sub { $selected_file = shift; },
        on_cancel => sub { $cancelled = 1; },
    );

    $picker->confirm();
    ok(defined $selected_file, 'on_select called');
    is($selected_file, $picker->filtered()->[0], 'Correct file passed');

    $cancelled = 0;
    $picker->cancel();
    is($cancelled, 1, 'on_cancel called');
};

# =============================================================================
# Scroll
# =============================================================================

subtest 'Scroll management' => sub {
    my $picker = Zepto::FilePicker->new(base_dir => $tmpdir);

    is($picker->scroll(), 0, 'Scroll initially 0');

    $picker->set_scroll(2);
    is($picker->scroll(), 2, 'set_scroll works');
};

done_testing();
