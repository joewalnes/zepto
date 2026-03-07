#!/usr/bin/env perl
# Tests for Zepto::FileSearchEngine
use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempdir tempfile);
use File::Path qw(mkpath);
use Cwd qw(getcwd abs_path);

use Zepto::FileSearchEngine;

# =============================================================================
# Construction
# =============================================================================

subtest 'Constructor defaults' => sub {
    my $engine = Zepto::FileSearchEngine->new();
    ok($engine, 'Engine created');
    is($engine->{done}, 1, 'Starts in done state');
    is($engine->{result_count}, 0, 'Zero results');
    is($engine->{query}, '', 'Empty query');
    is(scalar @{$engine->{results}}, 0, 'Empty results array');
};

# =============================================================================
# Backend Detection
# =============================================================================

subtest 'Backend detection' => sub {
    my $engine = Zepto::FileSearchEngine->new();

    # Detect backend for the project root (which is a git repo)
    my $cwd = getcwd();
    my $backend = $engine->detect_backend($cwd);
    ok($backend, "Detected backend: $backend");
    like($backend, qr/^(git_grep|rg|grep|perl)$/, 'Backend is one of the expected values');

    # Cached on second call
    my $backend2 = $engine->detect_backend('/nonexistent');
    is($backend2, $backend, 'Backend is cached after first detection');
};

subtest 'Backend detection in non-git dir' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $engine = Zepto::FileSearchEngine->new();
    my $backend = $engine->detect_backend($tmpdir);
    ok($backend, "Detected backend for non-git dir: $backend");
    isnt($backend, 'git_grep', 'Non-git dir does not use git_grep');
};

# =============================================================================
# Short/Empty Query
# =============================================================================

subtest 'Empty query does not search' => sub {
    my $engine = Zepto::FileSearchEngine->new();
    my $tmpdir = tempdir(CLEANUP => 1);
    $engine->detect_backend($tmpdir);

    $engine->search('', $tmpdir);
    is($engine->{done}, 1, 'No search started for empty query');
    is($engine->{result_count}, 0, 'Zero results for empty query');
};

subtest 'Single char query does not search' => sub {
    my $engine = Zepto::FileSearchEngine->new();
    my $tmpdir = tempdir(CLEANUP => 1);
    $engine->detect_backend($tmpdir);

    $engine->search('x', $tmpdir);
    is($engine->{done}, 1, 'No search started for single char');
    is($engine->{result_count}, 0, 'Zero results for single char');
};

# =============================================================================
# Invalid Scope
# =============================================================================

subtest 'Invalid scope directory' => sub {
    my $engine = Zepto::FileSearchEngine->new();
    $engine->detect_backend(getcwd());

    $engine->search('test', '/nonexistent/path/12345');
    is($engine->{done}, 1, 'No search for invalid scope dir');
};

# =============================================================================
# Pure Perl Fallback Search
# =============================================================================

subtest 'Pure Perl search finds matches' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);

    # Create test files
    _write_file("$tmpdir/hello.txt", "Hello World\nGoodbye World\nHello Again\n");
    _write_file("$tmpdir/other.txt", "No match here\n");
    mkpath("$tmpdir/sub");
    _write_file("$tmpdir/sub/nested.txt", "Hello from nested\n");

    my $engine = Zepto::FileSearchEngine->new();
    # Force pure Perl backend
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    $engine->search('hello', $tmpdir);
    is($engine->{done}, 0, 'Search started');

    # Tick until done
    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Search completed');
    ok($engine->{result_count} >= 3, "Found at least 3 results (got $engine->{result_count})");

    # Check result structure
    my $first = $engine->{results}[0];
    ok($first->{file}, 'Result has file path');
    ok($first->{display_path}, 'Result has display path');
    ok($first->{line_num}, 'Result has line number');
    ok(defined $first->{content}, 'Result has content');
};

# =============================================================================
# Result Capping
# =============================================================================

subtest 'Results capped at max' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);

    # Create a file with many matching lines
    my $content = '';
    for my $i (1 .. 1100) {
        $content .= "match line $i\n";
    }
    _write_file("$tmpdir/big.txt", $content);

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    $engine->search('match', $tmpdir);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 200) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Search completed');
    is($engine->{result_count}, 1000, 'Results capped at 1000');
    is(scalar @{$engine->{results}}, 1000, 'Results array capped at 1000');
};

# =============================================================================
# Abort
# =============================================================================

subtest 'Abort cleans up state' => sub {
    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    my $tmpdir = tempdir(CLEANUP => 1);
    _write_file("$tmpdir/test.txt", "hello world\n" x 100);

    $engine->search('hello', $tmpdir);
    $engine->abort();

    is($engine->{done}, 1, 'Done after abort');
    ok(!$engine->{_perl_fh}, 'File handle cleared after abort');
};

# =============================================================================
# is_searching
# =============================================================================

subtest 'is_searching reflects state' => sub {
    my $engine = Zepto::FileSearchEngine->new();
    ok(!$engine->is_searching(), 'Not searching initially');

    $engine->{done} = 0;
    ok($engine->is_searching(), 'Searching when done=0');

    $engine->{done} = 1;
    ok(!$engine->is_searching(), 'Not searching when done=1');
};

# =============================================================================
# Shell Metacharacters Safety
# =============================================================================

subtest 'Shell metacharacters in query are safe' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    _write_file("$tmpdir/test.txt", "normal line\n\$(rm -rf /)\nanother line\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    # Query with shell metacharacters - should not cause issues
    $engine->search('$(rm', $tmpdir);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Search with metacharacters completed safely');
    is($engine->{result_count}, 1, 'Found the literal match');
};

# =============================================================================
# Search with external tools (if available)
# =============================================================================

subtest 'Search with detected backend' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    # Resolve symlinks to match what search tools return
    $tmpdir = abs_path($tmpdir);
    _write_file("$tmpdir/test.txt", "Hello World\nGoodbye Moon\nHello Again\n");

    my $engine = Zepto::FileSearchEngine->new();
    my $backend = $engine->detect_backend($tmpdir);

    # Skip subprocess tests if only perl backend
    if ($backend eq 'perl') {
        pass("Only perl backend available, skipping subprocess test");
        return;
    }

    $engine->search('hello', $tmpdir);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 200) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, "Search completed with backend: $backend");
    ok($engine->{result_count} >= 2, "Found at least 2 results (got $engine->{result_count})");
};

# =============================================================================
# New search aborts previous
# =============================================================================

subtest 'New search aborts previous' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    _write_file("$tmpdir/test.txt", "hello world\ngoodbye world\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    $engine->search('hello', $tmpdir);
    my $first_id = $engine->{search_id};

    # Start new search before first completes
    $engine->search('goodbye', $tmpdir);
    my $second_id = $engine->{search_id};

    ok($second_id > $first_id, 'Search ID incremented');

    # Tick to completion
    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Second search completed');
    # Results should be for 'goodbye', not 'hello'
    for my $r (@{$engine->{results}}) {
        like(lc($r->{content}), qr/goodbye/, 'Result matches second query');
    }
};

# =============================================================================
# Line parsing
# =============================================================================

subtest 'Line parsing with colons in filename' => sub {
    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'grep';
    $engine->{_detected} = 1;
    $engine->{scope_dir} = '/tmp';
    $engine->{results} = [];
    $engine->{result_count} = 0;
    $engine->{_max_results} = 1000;

    # Simulate a grep output line
    $engine->{_buf} = "src/main.rs:42:fn main() {\n";
    $engine->_parse_lines('/tmp', 1);

    is($engine->{result_count}, 1, 'Parsed one result');
    is($engine->{results}[0]{display_path}, 'src/main.rs', 'Correct display path');
    is($engine->{results}[0]{line_num}, '42', 'Correct line number');
    like($engine->{results}[0]{content}, qr/fn main/, 'Correct content');
};

# =============================================================================
# Case-Sensitive Search
# =============================================================================

subtest 'Case-sensitive search (pure Perl)' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);

    _write_file("$tmpdir/test.txt", "Hello World\nhello world\nHELLO WORLD\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    # Case-sensitive: only match exact case "Hello"
    $engine->search('Hello', $tmpdir, case_sensitive => 1);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Case-sensitive search completed');
    is($engine->{result_count}, 1, 'Only 1 exact-case match for "Hello"');
    like($engine->{results}[0]{content}, qr/Hello World/, 'Matched the correct line');
};

subtest 'Case-insensitive search (pure Perl, default)' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);

    _write_file("$tmpdir/test.txt", "Hello World\nhello world\nHELLO WORLD\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    # Default (case-insensitive): match all 3 lines
    $engine->search('hello', $tmpdir);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Case-insensitive search completed');
    is($engine->{result_count}, 3, 'All 3 case variants matched');
};

# =============================================================================
# Regex Search
# =============================================================================

subtest 'Regex search (pure Perl)' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);

    _write_file("$tmpdir/test.txt", "foo bar\nbaz 123\nfoo 456\nbar baz\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    # Regex: match lines containing "foo" followed by a space and digits
    $engine->search('foo \d+', $tmpdir, use_regex => 1);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Regex search completed');
    is($engine->{result_count}, 1, 'Only 1 regex match');
    like($engine->{results}[0]{content}, qr/foo 456/, 'Matched the correct line');
};

subtest 'Case-sensitive regex search (pure Perl)' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);

    _write_file("$tmpdir/test.txt", "Foo bar\nfoo baz\nFOO qux\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    # Case-sensitive regex: only match lowercase "foo"
    $engine->search('foo', $tmpdir, case_sensitive => 1, use_regex => 1);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Case-sensitive regex search completed');
    is($engine->{result_count}, 1, 'Only 1 case-sensitive regex match');
    like($engine->{results}[0]{content}, qr/foo baz/, 'Matched the lowercase line');
};

subtest 'Invalid regex does not crash' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);

    _write_file("$tmpdir/test.txt", "hello world\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    # Invalid regex pattern
    $engine->search('[invalid', $tmpdir, use_regex => 1);

    # Should have aborted immediately
    is($engine->{done}, 1, 'Invalid regex aborts search');
    is($engine->{result_count}, 0, 'No results for invalid regex');
};

subtest 'Match position in results' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);

    _write_file("$tmpdir/test.txt", "the quick brown fox\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    $engine->search('quick', $tmpdir);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'Search completed');
    is($engine->{result_count}, 1, 'Found 1 match');
    is($engine->{results}[0]{match_col}, 4, 'match_col is correct (position of "quick")');
    is($engine->{results}[0]{match_len}, 5, 'match_len is correct');
};

# =============================================================================
# Helpers
# =============================================================================

sub _write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
}

done_testing();
