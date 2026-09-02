#!/usr/bin/env perl
# Regression test for bugs.md "Highlighter.pm has no timeout guard around
# grammar tokenize() regex matching" (QA-REG-233).
#
# None of the ~53 shipped grammars in Syntax/*.pm are known to contain a
# catastrophic-backtracking regex -- this is a structural gap (no safety
# net if one exists or is introduced), not a confirmed exploit in a real
# grammar. So this test constructs a synthetic pathological grammar
# (Test::Syntax::Pathological, defined below) and injects it directly into
# a Highlighter instance to prove the guard mechanism itself: any grammar's
# tokenize() call, however it misbehaves, cannot hang tokenize_line().
#
# Reproduction technique mirrors tests/find_engine_redos.t exactly, down to
# forking the risky call into a child bounded by a parent watchdog: Perl's
# alarm() is a single process-wide timer, so running the (possibly-broken)
# guard in-process could itself leave a stray alarm armed or never return,
# which would hang the test process rather than failing it cleanly.
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time sleep);
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use Zepto::Highlighter;
use Zepto::Syntax::Base;

# =============================================================================
# Synthetic pathological grammar
# =============================================================================
# (a?){N}a{N} is a genuinely catastrophic-backtracking pattern against
# Perl's own regex engine -- verified empirically in find_engine_redos.t
# (N=28 alone takes 15+ seconds of pure C-level backtracking on typical
# hardware). Reused here unchanged rather than re-deriving a new pathological
# pattern.
package Test::Syntax::Pathological;
use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

use constant EVIL_N => 28;
my $EVIL_RE = qr/(a?){${\ EVIL_N }}a{${\ EVIL_N }}/;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    # Deliberately naive: match the evil pattern against the whole line.
    # A real grammar's tokenize() loop tries many patterns per position;
    # this collapses that down to "one pathological match attempt" since
    # that's the unit the guard wraps.
    if ($line =~ /^($EVIL_RE)/) {
        push @tokens, Zepto::Syntax::Base::_token(0, length($1), TOKEN_KEYWORD);
    }
    return (\@tokens, STATE_NORMAL);
}

package main;

sub evil_line { return ('a' x Test::Syntax::Pathological::EVIL_N) }

# Build a Highlighter with the pathological grammar force-injected. There's
# no public API to register a one-off test grammar (by design -- grammars
# are registered by extension in Highlighter.pm's %EXTENSION_MAP for real
# use), so this pokes the blessed-hashref internals directly. This is
# white-box only for wiring the test grammar in; the guard itself is
# exercised through the public tokenize_line() call.
sub make_pathological_highlighter {
    my $hl = Zepto::Highlighter->new();
    $hl->{grammar}       = Test::Syntax::Pathological->new();
    $hl->{grammar_class} = 'Test::Syntax::Pathological';
    return $hl;
}

# Generous bound: with the fix, a single tokenize_line() call is capped at
# TOKENIZE_ALARM_SECS (0.1s in Highlighter.pm). 6s gives ample margin for
# process fork/load overhead on slow CI machines while remaining trivially
# far below "actually hung" (unfixed code takes 15s+ for the FIRST call).
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

subtest 'tokenize_line() does not hang on a catastrophic-backtracking grammar' => sub {
    my ($returned, $elapsed) = run_in_child(sub {
        my $hl = make_pathological_highlighter();
        $hl->tokenize_line(evil_line(), 0);
    });

    ok($returned, "tokenize_line() returned within ${\WATCHDOG_SECS}s watchdog (elapsed=${elapsed}s)")
        or diag("tokenize_line() did not return -- tokenize-time alarm did not fire");
};

subtest 'A pathological line times out promptly and falls back to plain text' => sub {
    my $hl = make_pathological_highlighter();

    my $start = time();
    my ($tokens, $end_state) = $hl->tokenize_line(evil_line(), 0);
    my $elapsed = time() - $start;

    ok($elapsed < 3, "tokenize_line() bounded to ~0.1s alarm, not left to run (got ${elapsed}s)");
    is_deeply($tokens, [], "timed-out line falls back to no tokens (plain/unhighlighted text)");
    ok($hl->highlight_timed_out, "highlight_timed_out() reports the tokenize-time timeout");
};

subtest 'A repeatedly-requested pathological line is not re-timed-out every call (cache absorbs it)' => sub {
    my $hl = make_pathological_highlighter();

    my $line = evil_line();
    my $first_start = time();
    $hl->tokenize_line($line, 0);
    my $first_elapsed = time() - $first_start;

    # Second call for the exact same (start_state, line_content) key must
    # hit the memo cache and return near-instantly, NOT re-run the guarded
    # tokenize() call and pay the alarm budget again -- this is what
    # prevents a persistently-pathological line from re-triggering the
    # timeout on every render frame (every scroll, every keystroke
    # elsewhere in the file).
    my $second_start = time();
    my ($tokens2) = $hl->tokenize_line($line, 0);
    my $second_elapsed = time() - $second_start;

    ok($first_elapsed > 0.05, "first call actually paid (most of) the alarm budget (got ${first_elapsed}s)");
    ok($second_elapsed < 0.02, "second call for the same line is a cache hit, not a re-timeout (got ${second_elapsed}s)");
    is_deeply($tokens2, [], "cached fallback is still empty tokens");
};

subtest 'highlight_timed_out() resets on set_file() (fresh unit of work)' => sub {
    my $hl = make_pathological_highlighter();
    $hl->tokenize_line(evil_line(), 0);
    ok($hl->highlight_timed_out, "flag set after a pathological line");

    # set_file() re-detects the grammar from the filename; use a .txt-ish
    # name with no grammar so we don't race a real grammar's tokenize().
    $hl->set_file('/tmp/highlighter-regex-timeout-test-no-such-ext.zzz_unknown_ext');
    ok(!$hl->highlight_timed_out, "flag cleared by set_file() (start of a new file's unit of work)");
};

subtest 'A real grammar error (non-timeout) still propagates, is not swallowed as a timeout' => sub {
    package Test::Syntax::Buggy;
    use parent 'Zepto::Syntax::Base';
    use Zepto::Syntax::Base;
    use strict;
    use warnings;
    sub tokenize { die "deliberate non-timeout grammar bug\n" }
    package main;

    my $hl = Zepto::Highlighter->new();
    $hl->{grammar}       = Test::Syntax::Buggy->new();
    $hl->{grammar_class} = 'Test::Syntax::Buggy';

    eval { $hl->tokenize_line('hello', 0) };
    like($@, qr/deliberate non-timeout grammar bug/,
        "a genuine grammar bug still dies with its own message, not silently treated as a timeout");
    ok(!$hl->highlight_timed_out, "highlight_timed_out() is not set by a non-timeout error");
};

subtest 'Normal (non-pathological) highlighting is completely unaffected' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.pl');

    my $start = time();
    my ($tokens, $state) = $hl->tokenize_line('my $x = 42; # a comment', 0);
    my $elapsed = time() - $start;

    ok(@$tokens > 0, "real Perl grammar still produces tokens for ordinary code");
    ok(!$hl->highlight_timed_out, "no timeout ever fires for ordinary, fast-matching content");
    ok($elapsed < 0.05, "ordinary tokenization is fast, nowhere near the alarm budget (got ${elapsed}s)");
};

done_testing();
