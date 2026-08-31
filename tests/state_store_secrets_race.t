#!/usr/bin/env perl
# QA-REG-194 / bugs.md P2 "AI API key briefly written world-readable
# before chmod 0600 catches up".
#
# StateStore::put() for the 'secrets' category must never let its temp
# file exist on disk at a world- or group-readable mode, even for a
# moment. The original bug: `open my $fh, '>', $tmp_path` creates the
# file at the process's default umask permissions (often 0644), and only
# a *later* `chmod 0600` (after write + close) narrows it down — a real
# window where the file is world-readable while the secret content is
# being written.
#
# Checking the FINAL file's permissions after put() returns would NOT
# catch this — both the buggy code and the fixed code end up at 0600.
# To actually catch the race, this test intercepts the file-creation
# syscall itself (open/sysopen) by overriding CORE::GLOBAL::open and
# CORE::GLOBAL::sysopen *before* Zepto::StateStore is compiled (a BEGIN
# block, required for a CORE::GLOBAL override to take effect on code
# compiled afterward — see perlsub "Overriding Built-in Functions").
# Every time StateStore creates our target secrets tmp file, we record
# the file's mode on disk immediately after creation returns — before
# StateStore has had any chance to write content, close, chmod, or
# rename it. This is deterministic (no timing/sleep/polling involved),
# so it can't flake, and it reproduces the exact original bug: run this
# against the pre-fix code (a plain `open` + later `chmod 0600`) and it
# fails because the file is observed at the permissive umask-default
# mode at creation time.
use strict;
use warnings;

# IMPORTANT: every module StateStore.pm depends on (transitively) must be
# fully loaded and COMPILED *before* we install the CORE::GLOBAL::open /
# CORE::GLOBAL::sysopen overrides below. Overriding a builtin changes how
# `open`/`sysopen` are parsed (not just their runtime behavior) for every
# piece of code compiled *after* the override is installed — code using
# the classic bareword-filehandle form (`open(REALPATH, ...)`, which
# Cwd.pm's internals use) fails to compile under an override with no
# matching special-case parsing. Loading everything up front confines the
# override's effect to exactly what we want to instrument: StateStore.pm
# itself, `require`d further down after the override is in place.
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Fcntl;
use Cwd;
use JSON::PP ();
use lib 'lib';

my @observed;   # { path => ..., mode => ... } for every creation of our target file

BEGIN {
    no warnings 'redefine';

    *CORE::GLOBAL::open = sub {
        my $ret;
        if (@_ == 3) {
            $ret = CORE::open($_[0], $_[1], $_[2]);
        } elsif (@_ == 2) {
            $ret = CORE::open($_[0], $_[1]);
        } else {
            $ret = CORE::open($_[0]);
        }
        my $target = $_[-1];
        if ($ret && defined $target && !ref($target) && $target =~ /secrets\.json\.tmp\./) {
            my @st = stat($target);
            push @observed, { path => $target, mode => $st[2] & 07777, via => 'open' } if @st;
        }
        return $ret;
    };

    *CORE::GLOBAL::sysopen = sub {
        my ($fh, $path, $flags, $mode) = @_;
        my $ret = (@_ >= 4)
            ? CORE::sysopen($_[0], $path, $flags, $mode)
            : CORE::sysopen($_[0], $path, $flags);
        if ($ret && defined $path && $path =~ /secrets\.json\.tmp\./) {
            my @st = stat($path);
            push @observed, { path => $path, mode => $st[2] & 07777, via => 'sysopen' } if @st;
        }
        return $ret;
    };
}

# require (not use) — the override above must be installed before this
# module is compiled for the instrumentation to see its open/sysopen calls.
require Zepto::StateStore;

my $dir = tempdir(CLEANUP => 1);
my $store = Zepto::StateStore->new(base_dir => $dir);

# Force a permissive umask so a regression to a plain `open` (default
# mode 0666) would definitely be caught, exactly like a real multi-user
# box with a permissive default umask. sysopen() with an explicit literal
# mode of 0600 is immune to umask making it MORE permissive than
# requested (umask can only clear bits, never set them), so this doesn't
# affect the fixed code's correctness.
my $old_umask = umask(0022);
$store->put('secrets', { api_key => 'sk-test-race-window-12345' });
umask($old_umask);

ok(scalar(@observed) > 0,
    'instrumentation actually intercepted the secrets tmp file creation (sanity check the test itself is wired up)')
    or diag('No open()/sysopen() call for a *secrets.json.tmp.* path was observed - test harness is broken, not just the feature');

my $worst_group_other_bits = 0;
for my $obs (@observed) {
    $worst_group_other_bits |= ($obs->{mode} & 07077);
}

is($worst_group_other_bits, 0,
    'secrets temp file is never group/world readable or writable at ANY point during creation (checked at the moment of open/sysopen, before write/close/chmod/rename ever run) - not just after the final chmod')
    or diag('Observed modes: ' . join(', ', map { sprintf('%s via %s: %04o', $_->{path}, $_->{via}, $_->{mode}) } @observed));

# Final on-disk file must also still be 0600, as before.
my @final_stat = stat("$dir/secrets.json");
is(sprintf('%04o', $final_stat[2] & 07777), '0600', 'final secrets.json file is mode 0600');

done_testing;
