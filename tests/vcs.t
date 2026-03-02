#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Cwd qw(getcwd abs_path);

use Zepto::VCS::Provider;
use Zepto::VCS::Git;

# =============================================================================
# Provider base class tests
# =============================================================================

subtest 'Provider detection with no repo' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $file = "$tempdir/test.txt";
    open my $fh, '>', $file or die "Cannot create $file: $!";
    print $fh "test content\n";
    close $fh;

    my $provider = Zepto::VCS::Provider->detect($file);
    is($provider, undef, 'No provider detected for file outside repo');
};

subtest 'Provider detection with invalid path' => sub {
    my $provider = Zepto::VCS::Provider->detect(undef);
    is($provider, undef, 'No provider for undef path');

    $provider = Zepto::VCS::Provider->detect('/nonexistent/path/file.txt');
    is($provider, undef, 'No provider for nonexistent path');
};

# =============================================================================
# Git provider tests
# =============================================================================

# Check if git is available for testing
my $git_available = do {
    my $result = `git --version 2>/dev/null`;
    $? == 0;
};

SKIP: {
    skip "git not available", 8 unless $git_available;

    subtest 'Git detection finds .git directory' => sub {
        my $tempdir = tempdir(CLEANUP => 1);

        # Initialize a git repo
        system("cd $tempdir && git init --quiet 2>/dev/null");

        # Create a file
        my $file = "$tempdir/test.txt";
        open my $fh, '>', $file or die "Cannot create $file: $!";
        print $fh "test content\n";
        close $fh;

        my $provider = Zepto::VCS::Git->detect($file);
        ok(defined $provider, 'Git provider detected');
        is($provider->name, 'git', 'Provider name is git');
        # Resolve symlinks for comparison (macOS /var -> /private/var)
        is(abs_path($provider->repo_root), abs_path($tempdir), 'Repo root is correct');
    };

    subtest 'Git detection in subdirectory' => sub {
        my $tempdir = tempdir(CLEANUP => 1);

        # Initialize a git repo
        system("cd $tempdir && git init --quiet 2>/dev/null");

        # Create a subdirectory with a file
        make_path("$tempdir/sub/dir");
        my $file = "$tempdir/sub/dir/test.txt";
        open my $fh, '>', $file or die "Cannot create $file: $!";
        print $fh "test content\n";
        close $fh;

        my $provider = Zepto::VCS::Git->detect($file);
        ok(defined $provider, 'Git provider detected in subdirectory');
        is(abs_path($provider->repo_root), abs_path($tempdir), 'Repo root found from subdirectory');
    };

    subtest 'Git is_tracked for tracked file' => sub {
        my $tempdir = tempdir(CLEANUP => 1);

        # Initialize repo and add a file
        system("cd $tempdir && git init --quiet 2>/dev/null");
        system("cd $tempdir && git config user.email 'test\@test.com' && git config user.name 'Test' && git config commit.gpgsign false");

        my $file = "$tempdir/tracked.txt";
        open my $fh, '>', $file or die "Cannot create $file: $!";
        print $fh "tracked content\n";
        close $fh;

        system("cd $tempdir && git add tracked.txt && git commit -m 'Add file' --quiet 2>/dev/null");

        my $provider = Zepto::VCS::Git->detect($file);
        ok($provider->is_tracked($file), 'Tracked file is detected as tracked');
    };

    subtest 'Git is_tracked for untracked file' => sub {
        my $tempdir = tempdir(CLEANUP => 1);

        # Initialize repo
        system("cd $tempdir && git init --quiet 2>/dev/null");

        my $file = "$tempdir/untracked.txt";
        open my $fh, '>', $file or die "Cannot create $file: $!";
        print $fh "untracked content\n";
        close $fh;

        my $provider = Zepto::VCS::Git->detect($file);
        ok(!$provider->is_tracked($file), 'Untracked file is detected as untracked');
    };

    subtest 'Git get_head_content' => sub {
        my $tempdir = tempdir(CLEANUP => 1);

        # Initialize repo and commit a file
        system("cd $tempdir && git init --quiet 2>/dev/null");
        system("cd $tempdir && git config user.email 'test\@test.com' && git config user.name 'Test' && git config commit.gpgsign false");

        my $file = "$tempdir/test.txt";
        open my $fh, '>', $file or die "Cannot create $file: $!";
        print $fh "original content\n";
        close $fh;

        system("cd $tempdir && git add test.txt && git commit -m 'Add file' --quiet 2>/dev/null");

        # Modify the file (working tree)
        open $fh, '>', $file or die "Cannot write $file: $!";
        print $fh "modified content\n";
        close $fh;

        my $provider = Zepto::VCS::Git->detect($file);
        my $head_content = $provider->get_head_content($file);

        is($head_content, "original content", 'HEAD content is original (without trailing newline)');
    };

    subtest 'Git get_head_content for new file' => sub {
        my $tempdir = tempdir(CLEANUP => 1);

        # Initialize repo
        system("cd $tempdir && git init --quiet 2>/dev/null");
        system("cd $tempdir && git config user.email 'test\@test.com' && git config user.name 'Test' && git config commit.gpgsign false");

        # Create initial commit so HEAD exists
        my $dummy = "$tempdir/dummy.txt";
        open my $fh, '>', $dummy or die "Cannot create $dummy: $!";
        print $fh "dummy\n";
        close $fh;
        system("cd $tempdir && git add dummy.txt && git commit -m 'Initial' --quiet 2>/dev/null");

        # Create new untracked file
        my $file = "$tempdir/new.txt";
        open $fh, '>', $file or die "Cannot create $file: $!";
        print $fh "new content\n";
        close $fh;

        my $provider = Zepto::VCS::Git->detect($file);
        my $head_content = $provider->get_head_content($file);

        is($head_content, undef, 'HEAD content is undef for new file');
    };

    subtest 'Git content with UTF-8' => sub {
        my $tempdir = tempdir(CLEANUP => 1);

        # Initialize repo
        system("cd $tempdir && git init --quiet 2>/dev/null");
        system("cd $tempdir && git config user.email 'test\@test.com' && git config user.name 'Test' && git config commit.gpgsign false");

        my $file = "$tempdir/utf8.txt";
        open my $fh, '>:encoding(UTF-8)', $file or die "Cannot create $file: $!";
        print $fh "Hello 世界\nПривет мир\n";
        close $fh;

        system("cd $tempdir && git add utf8.txt && git commit -m 'Add UTF-8' --quiet 2>/dev/null");

        my $provider = Zepto::VCS::Git->detect($file);
        my $head_content = $provider->get_head_content($file);

        like($head_content, qr/世界/, 'UTF-8 content retrieved correctly');
        like($head_content, qr/Привет/, 'Cyrillic UTF-8 content retrieved correctly');
    };

    subtest 'Git cache invalidation' => sub {
        my $tempdir = tempdir(CLEANUP => 1);

        # Initialize repo
        system("cd $tempdir && git init --quiet 2>/dev/null");
        system("cd $tempdir && git config user.email 'test\@test.com' && git config user.name 'Test' && git config commit.gpgsign false");

        my $file = "$tempdir/test.txt";
        open my $fh, '>', $file or die "Cannot create $file: $!";
        print $fh "version 1\n";
        close $fh;

        system("cd $tempdir && git add test.txt && git commit -m 'v1' --quiet 2>/dev/null");

        my $provider = Zepto::VCS::Git->detect($file);

        # First read (cached)
        my $v1 = $provider->get_head_content($file);
        is($v1, "version 1", 'First read correct');

        # Modify and commit
        open $fh, '>', $file or die "Cannot write $file: $!";
        print $fh "version 2\n";
        close $fh;
        system("cd $tempdir && git add test.txt && git commit -m 'v2' --quiet 2>/dev/null");

        # Still cached
        my $still_v1 = $provider->get_head_content($file);
        is($still_v1, "version 1", 'Still returns cached version');

        # Invalidate and re-read
        $provider->invalidate_cache($file);
        my $v2 = $provider->get_head_content($file);
        is($v2, "version 2", 'After invalidation, returns new version');
    };
}

# =============================================================================
# Test this repo (if we're in a git repo)
# =============================================================================

SKIP: {
    skip "Not in a git repo or git not available", 1 unless $git_available;

    my $this_file = abs_path(__FILE__);
    my $provider = Zepto::VCS::Provider->detect($this_file);

    skip "This test file is not in a git repo", 1 unless $provider;

    subtest 'Detection works on this repo' => sub {
        ok(defined $provider, 'Provider detected for test file');
        is($provider->name, 'git', 'This repo uses git');
        ok(-d $provider->repo_root . '/.git', 'Repo root has .git directory');
    };
}

done_testing();
