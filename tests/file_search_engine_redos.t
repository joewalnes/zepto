#!/usr/bin/env perl
# Regression test for bugs.md P1 "FileSearchEngine.pm's 'Find in Files'
# regex search has no match-time ReDoS timeout, only compile-time"
# (QA-REG-207).
#
# _start_perl_search()'s alarm(1) only guards qr// *compilation* and is
# explicitly cancelled before the caller ever attempts a match. Catastrophic
# backtracking happens at MATCH time -- $content =~ $re in
# _find_match_in_content() and $line =~ $perl_regex inside _tick_perl()'s
# scan loop both ran with no timeout at all, so a pathological pattern
# could hang the async "Find in Files" search indefinitely. This is the
# exact same gap FindEngine.pm (in-buffer find/replace) already fixed --
# see tests/find_engine_redos.t and FindEngine.pm:505-572 -- just never
# applied to this sibling project-wide search engine.
#
# NOTE: Perl's alarm() is a single process-wide timer. FileSearchEngine's
# own internal alarm(1)/alarm(0) around regex *compilation* would clobber
# any alarm we set in-process around the *call* to tick()/search(), which
# would make an in-process watchdog unable to reliably distinguish "fixed"
# from "broken" here. So the risky call is done in a forked CHILD process,
# bounded by a watchdog in the PARENT that doesn't share the child's
# alarm() state at all. Mirrors tests/find_engine_redos.t exactly.
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time sleep);
use File::Temp qw(tempdir);
use lib 'lib';

use Zepto::FileSearchEngine;

# (a?){N}a{N} is a genuinely catastrophic-backtracking pattern against
# Perl's own regex engine -- verified empirically (N=28 alone takes 15+
# seconds of pure C-level backtracking on typical hardware). Perl's engine
# auto-optimizes away some textbook ReDoS demos like `(a+)+$` (it collapses
# nested quantifiers over identical single-char atoms), so that classic
# example does NOT reproduce this bug in Perl -- this counted-repetition-
# of-optional form does.
use constant EVIL_N => 28;
my $EVIL_PATTERN = '(a?){' . EVIL_N . '}a{' . EVIL_N . '}';

# Generous bound: with the fix, a single pathological match attempt is
# capped at MATCH_ALARM_SECS (1s in FileSearchEngine.pm). 8s gives ample
# margin for process fork/load overhead on slow CI machines while
# remaining trivially far below "actually hung" (unfixed code takes 15s+
# for the FIRST match attempt alone).
use constant WATCHDOG_SECS => 8;

sub run_in_child {
    my ($coderef) = @_;

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        $coderef->();
        exit 0;
    }

    my $start = time();
    my $deadline = $start + WATCHDOG_SECS;
    my $reaped = 0;
    while (time() < $deadline) {
        my $r = waitpid($pid, 1);    # WNOHANG
        if ($r == $pid) { $reaped = 1; last; }
        sleep(0.02);
    }

    my $elapsed = time() - $start;

    if (!$reaped) {
        kill 'KILL', $pid;
        waitpid($pid, 0);
        return (0, $elapsed);
    }

    return (1, $elapsed);
}

sub _write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
}

subtest 'Pure-Perl tick() scan does not hang on catastrophic backtracking' => sub {
    my ($returned, $elapsed) = run_in_child(sub {
        my $tmpdir = tempdir(CLEANUP => 1);
        _write_file("$tmpdir/victim.txt", ('a' x EVIL_N) . "\n");

        my $engine = Zepto::FileSearchEngine->new();
        $engine->{_backend} = 'perl';
        $engine->{_detected} = 1;
        $engine->search($EVIL_PATTERN, $tmpdir, use_regex => 1, case_sensitive => 1);

        my $ticks = 0;
        while (!$engine->{done}) {
            $engine->tick(30);
            $ticks++;
            die "tick loop did not terminate\n" if $ticks > 1000;
        }
    });

    ok($returned, "tick() loop terminated within ${\WATCHDOG_SECS}s watchdog (elapsed=${elapsed}s)")
        or diag("tick() loop hung or never terminated -- match-time alarm did not fire");
};

subtest 'search_timed_out() flag and graceful completion after a match-time timeout' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    _write_file("$tmpdir/victim.txt", ('a' x EVIL_N) . "\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;
    $engine->search($EVIL_PATTERN, $tmpdir, use_regex => 1, case_sensitive => 1);

    my $start = time();
    my $ticks = 0;
    my $result;
    while (!$engine->{done} && $ticks < 200) {
        $result = $engine->tick(30);
        $ticks++;
    }
    my $elapsed = time() - $start;

    ok($elapsed < 5, "search bounded to ~1s match alarm, not left to run (got ${elapsed}s)");
    ok($engine->{done}, "search reaches done=1 instead of wedging forever");
    ok($engine->search_timed_out, "search_timed_out() reports the match-time timeout");
    is($engine->{result_count}, 0, "no crash / no false match recorded for the timed-out line");
};

subtest 'Timeout on one line does not abort the whole file/search -- other matches still found' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $content = "normal line one\n"
                . ('a' x EVIL_N) . "\n"          # pathological line -- should be skipped, not fatal
                . "normal line two with hello\n";
    _write_file("$tmpdir/mixed.txt", $content);

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;
    # Pattern matches ordinary text fine, but explodes against the evil line
    # because of the leading (a?){28} alternation this pattern is embedded in.
    my $pattern = '(a?){' . EVIL_N . '}a{' . EVIL_N . '}|hello';
    $engine->search($pattern, $tmpdir, use_regex => 1, case_sensitive => 1);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 200) {
        $engine->tick(30);
        $ticks++;
    }

    ok($engine->{done}, "search completes despite one pathological line");
    ok($engine->search_timed_out, "timeout flag set for the pathological line");
    is($engine->{result_count}, 1, "the unrelated 'hello' match on another line is still found");
    like($engine->{results}[0]{content}, qr/hello/, "surviving match content is correct");
};

subtest 'Normal (non-catastrophic) regex search across many files is unaffected' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    for my $i (1 .. 20) {
        _write_file("$tmpdir/file$i.txt", "the quick brown fox $i\nirrelevant line $i\n");
    }

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;

    my $start = time();
    $engine->search('quick \w+ fox', $tmpdir, use_regex => 1);
    my $ticks = 0;
    while (!$engine->{done} && $ticks < 200) {
        $engine->tick(30);
        $ticks++;
    }
    my $elapsed = time() - $start;

    ok(!$engine->search_timed_out, "normal search across 20 files is not falsely flagged as timed out");
    is($engine->{result_count}, 20, "all 20 legitimate matches found (fix doesn't drop real results)");
    ok($elapsed < 2, "normal search over 20 small files completes quickly (got ${elapsed}s)");
};

subtest 'Match position/highlighting through _find_match_in_content is unaffected by the guard' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    _write_file("$tmpdir/pos.txt", "the quick brown fox\n");

    my $engine = Zepto::FileSearchEngine->new();
    $engine->{_backend} = 'perl';
    $engine->{_detected} = 1;
    $engine->search('quick', $tmpdir, use_regex => 1);

    my $ticks = 0;
    while (!$engine->{done} && $ticks < 100) {
        $engine->tick(50);
        $ticks++;
    }

    ok($engine->{done}, 'search completed');
    is($engine->{result_count}, 1, 'found 1 match');
    is($engine->{results}[0]{match_col}, 4, 'match_col is correct (position of "quick")');
    is($engine->{results}[0]{match_len}, 5, 'match_len is correct');
    ok(!$engine->search_timed_out, 'no timeout on a normal match');
};

done_testing();
