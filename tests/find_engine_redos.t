#!/usr/bin/env perl
# Regression test for bugs.md P1 "FindEngine.pm ReDoS timeout only covers
# regex compilation, not matching" (QA-REG-141).
#
# _build_regex()'s alarm(1) only guards qr// *compilation* and is
# explicitly cancelled before the caller ever attempts a match.
# Catastrophic backtracking happens at MATCH time, so a pathological
# pattern could hang tick()/_search_range() indefinitely even though
# compilation itself was instant.
#
# NOTE: Perl's alarm() is a single process-wide timer. FindEngine's own
# internal alarm(1)/alarm(0) around regex *compilation* would clobber any
# alarm we set in-process around the *call* to search(), which would make
# an in-process watchdog unable to reliably distinguish "fixed" from
# "broken" here. So the risky call is done in a forked CHILD process,
# bounded by a watchdog in the PARENT that doesn't share the child's
# alarm() state at all.
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time sleep);
use lib 'lib';

use Zepto::FindEngine;
use Zepto::Document;

# (a?){N}a{N} is a genuinely catastrophic-backtracking pattern against
# Perl's own regex engine -- verified empirically (N=28 alone takes 15+
# seconds of pure C-level backtracking on typical hardware). Perl's
# engine auto-optimizes away some textbook ReDoS demos like `(a+)+$` (it
# collapses nested quantifiers over identical single-char atoms), so
# that classic example does NOT reproduce this bug in Perl -- this
# counted-repetition-of-optional form does.
use constant EVIL_N => 28;
my $EVIL_PATTERN = '(a?){' . EVIL_N . '}a{' . EVIL_N . '}';

# Generous bound: with the fix, a single pathological match attempt is
# capped at MATCH_ALARM_SECS (1s in FindEngine.pm). 6s gives ample margin
# for process fork/load overhead on slow CI machines while remaining
# trivially far below "actually hung" (unfixed code takes 15s+ just for
# the FIRST match attempt, and would retry indefinitely).
use constant WATCHDOG_SECS => 6;

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

subtest 'Synchronous viewport search does not hang on catastrophic backtracking' => sub {
    my ($returned, $elapsed) = run_in_child(sub {
        my $doc = Zepto::Document->new();
        $doc->insert(0, ('a' x EVIL_N) . "\n");
        my $engine = Zepto::FindEngine->new(document => $doc);
        # Synchronous viewport search -- the vulnerable path in search(),
        # called on every keystroke in the find bar.
        $engine->search($EVIL_PATTERN, 0, 10, use_regex => 1);
    });

    ok($returned, "search() returned within ${\WATCHDOG_SECS}s watchdog (elapsed=${elapsed}s)")
        or diag("search() did not return -- match-time alarm did not fire");
};

subtest 'Background tick() search does not hang on catastrophic backtracking' => sub {
    my ($returned, $elapsed) = run_in_child(sub {
        my $doc = Zepto::Document->new();
        my $text = '';
        $text .= "line $_\n" for (1 .. 5);
        $text .= ('a' x EVIL_N) . "\n";    # outside the viewport search
        $doc->insert(0, $text);
        my $engine = Zepto::FindEngine->new(document => $doc);
        # Viewport only covers lines 0-2, so the pathological line is
        # only ever reached by the background tick() loop.
        $engine->search($EVIL_PATTERN, 0, 2, use_regex => 1);

        my $ticks = 0;
        while ($engine->is_searching) {
            $engine->tick(10);
            $ticks++;
            die "tick loop did not terminate\n" if $ticks > 1000;
        }
    });

    ok($returned, "tick() loop terminated within ${\WATCHDOG_SECS}s watchdog (elapsed=${elapsed}s)")
        or diag("tick() loop hung or never terminated");
};

subtest 'search_timed_out() flag and results after a match-time timeout' => sub {
    my $doc = Zepto::Document->new();
    $doc->insert(0, ('a' x EVIL_N) . "\n");
    my $engine = Zepto::FindEngine->new(document => $doc);

    my $start = time();
    my $matches = $engine->search($EVIL_PATTERN, 0, 10, use_regex => 1);
    my $elapsed = time() - $start;

    ok($elapsed < 3, "viewport search bounded to ~1s alarm, not left to run (got ${elapsed}s)");
    ok($engine->search_timed_out, "search_timed_out() reports the match-time timeout");
    is(ref($matches), 'ARRAY', "search() still returns an arrayref, not undef/die, on timeout");
};

subtest 'search_timed_out() flag resets on the next (non-pathological) search' => sub {
    my $doc = Zepto::Document->new();
    $doc->insert(0, ('a' x EVIL_N) . "\nhello world\n");
    my $engine = Zepto::FindEngine->new(document => $doc);

    $engine->search($EVIL_PATTERN, 0, 10, use_regex => 1);
    ok($engine->search_timed_out, "flag set after pathological search");

    $engine->search('hello', 0, 10);
    while ($engine->is_searching) { $engine->tick(50); }
    ok(!$engine->search_timed_out, "flag cleared after a subsequent normal search");
    is($engine->match_count, 1, "normal search after a timeout still finds matches correctly");
};

subtest 'Normal (non-catastrophic) search is unaffected -- no false positives' => sub {
    my $doc = Zepto::Document->new();
    my $text = '';
    $text .= "hello world line $_\n" for (1 .. 2000);
    $doc->insert(0, $text);
    my $engine = Zepto::FindEngine->new(document => $doc);

    my $start = time();
    $engine->search('hello', 0, 50);
    while ($engine->is_searching) { $engine->tick(10); }
    my $elapsed = time() - $start;

    ok(!$engine->search_timed_out, "large but non-pathological search is not falsely flagged as timed out");
    is($engine->match_count, 2000, "all 2000 matches found (fix doesn't truncate legitimate results)");
    ok($elapsed < 1, "normal search over 2000 lines completes quickly (got ${elapsed}s)");
};

subtest 'Capture group extraction still works correctly through the fix' => sub {
    # Regression guard for a bug found WHILE building this fix: an
    # earlier version of the alarm wrapper read $1 after the guarding
    # eval{} block returned, which silently discarded it (Perl's
    # numbered match variables don't reliably survive being read from
    # outside a multi-statement eval{}). The fix reads $1/@-/@+ INSIDE
    # the eval and returns already-extracted plain values. This test
    # would fail with "uninitialized value" warnings / wrong captures if
    # that regressed.
    my $doc = Zepto::Document->new();
    $doc->insert(0, "foo123 bar456\n");
    my $engine = Zepto::FindEngine->new(document => $doc);
    $engine->search('(\w+?)(\d+)', 0, 10, use_regex => 1);
    while ($engine->is_searching) { $engine->tick(50); }

    is($engine->capture_group_count, 2, "capture group count correct");

    my $preview = $engine->preview_line(0, '[$1]-[$2]');
    is($preview->{text}, '[foo]-[123] [bar]-[456]', "capture references expand correctly");
};

done_testing();
