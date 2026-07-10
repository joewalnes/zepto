#!/usr/bin/env perl
# Tests for Zepto::HangWatchdog (bugs.md/CLAUDE.md Phase 2 item 7: hang
# watchdog — fork-based, no threads in this codebase).
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time sleep);
use File::Temp qw(tempdir);
use lib 'lib';

use Zepto::HangWatchdog;

# ============================================================================
# Basic lifecycle: start/stop, no zombies
# ============================================================================

subtest 'start returns a handle with pid and write_fh' => sub {
    my $log_dir = tempdir(CLEANUP => 1);
    my $wd = Zepto::HangWatchdog::start(log_dir => $log_dir, threshold => 2);
    ok($wd, 'Watchdog started');
    ok($wd->{pid}, 'Handle has a pid');
    ok($wd->{write_fh}, 'Handle has a write filehandle');

    # Confirm the process actually exists
    ok(kill(0, $wd->{pid}), 'Watchdog process is alive');

    Zepto::HangWatchdog::stop($wd);

    # Give the OS a moment, then confirm it's gone and not a zombie
    my $deadline = time() + 2;
    my $gone = 0;
    while (time() < $deadline) {
        if (!kill(0, $wd->{pid})) { $gone = 1; last; }
        Time::HiRes::sleep(0.05);
    }
    ok($gone, 'Watchdog process exited after stop()');
};

subtest 'stop() is a no-op on an undef watchdog (disabled case)' => sub {
    my $ok = eval { Zepto::HangWatchdog::stop(undef); 1 };
    ok($ok, 'stop(undef) does not die');
};

subtest 'heartbeat() is a no-op on an undef watchdog (disabled case)' => sub {
    my $ok = eval { Zepto::HangWatchdog::heartbeat(undef, 'loop'); 1 };
    ok($ok, 'heartbeat(undef, ...) does not die');
};

# ============================================================================
# Heartbeats prevent false-positive hang detection
# ============================================================================

subtest 'regular heartbeats keep the watchdog quiet (no log written)' => sub {
    my $log_dir = tempdir(CLEANUP => 1);
    my $wd = Zepto::HangWatchdog::start(log_dir => $log_dir, threshold => 1);
    ok($wd, 'Watchdog started');

    # Heartbeat well within the threshold, for longer than the threshold
    # would otherwise allow, to prove regular heartbeats suppress firing.
    for (1 .. 6) {
        Zepto::HangWatchdog::heartbeat($wd, 'loop');
        Time::HiRes::sleep(0.1);
    }

    opendir(my $dh, $log_dir);
    my @logs = grep { /^hang-/ } readdir($dh);
    closedir($dh);
    is(scalar @logs, 0, 'No hang log written while heartbeats are regular');

    Zepto::HangWatchdog::stop($wd);
};

# ============================================================================
# Hang detection: no heartbeat -> log + SIGUSR2
# ============================================================================

subtest 'no heartbeat within threshold triggers a diagnostic log and SIGUSR2' => sub {
    my $log_dir = tempdir(CLEANUP => 1);

    my $got_usr2 = 0;
    local $SIG{USR2} = sub { $got_usr2 = 1; };

    my $wd = Zepto::HangWatchdog::start(log_dir => $log_dir, threshold => 0.3);
    ok($wd, 'Watchdog started');

    # Send one heartbeat so the watchdog has a "last tag" to report, then
    # go silent (simulate a wedged main loop) past the threshold.
    Zepto::HangWatchdog::heartbeat($wd, 'test-marker-tag');

    my $deadline = time() + 5;
    while (time() < $deadline && !$got_usr2) {
        Time::HiRes::sleep(0.1);
    }
    ok($got_usr2, 'SIGUSR2 was received after silence past the threshold');

    my $log_path = Zepto::HangWatchdog::most_recent_log($log_dir);
    ok($log_path, 'A hang log file was written');
    ok(-e $log_path, 'Log file actually exists on disk');

    open(my $fh, '<', $log_path) or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;
    like($content, qr/hang detected/i, 'Log mentions hang detection');
    like($content, qr/test-marker-tag/, 'Log records the last heartbeat tag');
    like($content, qr/pid: \d+/, 'Log records the parent pid');

    Zepto::HangWatchdog::stop($wd);
};

subtest 'watchdog does not re-fire repeatedly for the same stretch of silence' => sub {
    my $log_dir = tempdir(CLEANUP => 1);
    my $usr2_count = 0;
    local $SIG{USR2} = sub { $usr2_count++; };

    my $wd = Zepto::HangWatchdog::start(log_dir => $log_dir, threshold => 0.3);
    Zepto::HangWatchdog::heartbeat($wd, 'once');

    # Stay silent for several threshold windows.
    Time::HiRes::sleep(1.2);

    ok($usr2_count >= 1, 'Fired at least once');
    ok($usr2_count <= 2, "Did not spam-fire every threshold window (count=$usr2_count)");

    Zepto::HangWatchdog::stop($wd);
};

# ============================================================================
# most_recent_log()
# ============================================================================

subtest 'most_recent_log returns undef for an empty/missing directory' => sub {
    my $log_dir = tempdir(CLEANUP => 1);
    is(Zepto::HangWatchdog::most_recent_log($log_dir), undef, 'undef when no logs exist');
    is(Zepto::HangWatchdog::most_recent_log("$log_dir/does-not-exist"), undef, 'undef for missing dir');
};

subtest 'most_recent_log finds the newest hang-*.log file' => sub {
    my $log_dir = tempdir(CLEANUP => 1);
    for my $name (qw(hang-20260101-000000.log hang-20260101-000001.log)) {
        open(my $fh, '>', "$log_dir/$name") or die $!;
        print $fh "x";
        close $fh;
        utime(time(), time(), "$log_dir/$name");
        Time::HiRes::sleep(0.05);
    }
    # Touch the second one again so it's unambiguously newest by mtime.
    my $newest_path = "$log_dir/hang-20260101-000001.log";
    utime(time() + 10, time() + 10, $newest_path);

    is(Zepto::HangWatchdog::most_recent_log($log_dir), $newest_path, 'Newest file by mtime is returned');
};

# ============================================================================
# Log content sanitization (security review follow-up): the heartbeat tag
# can embed arbitrary user-typed text (e.g. "transform:$cmd" for a shell
# transform command) — control/escape characters must not reach the log
# file verbatim, since a human debugging a hang will `cat` it.
# ============================================================================

subtest 'diagnostic log strips control/escape characters from the heartbeat tag' => sub {
    my $log_dir = tempdir(CLEANUP => 1);
    my $got_usr2 = 0;
    local $SIG{USR2} = sub { $got_usr2 = 1; };

    my $wd = Zepto::HangWatchdog::start(log_dir => $log_dir, threshold => 0.3);
    ok($wd, 'Watchdog started');

    # A tag containing a raw ESC byte + OSC-looking sequence — as if a
    # shell transform command with an embedded escape sequence were used
    # as the heartbeat tag.
    my $malicious_tag = "transform:sleep 30\x1b]0;pwned\x07";
    Zepto::HangWatchdog::heartbeat($wd, $malicious_tag);

    my $deadline = time() + 3;
    while (time() < $deadline && !$got_usr2) {
        Time::HiRes::sleep(0.1);
    }
    ok($got_usr2, 'Watchdog fired');

    my $log_path = Zepto::HangWatchdog::most_recent_log($log_dir);
    ok($log_path, 'Log file written');

    open(my $fh, '<', $log_path) or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;

    unlike($content, qr/\x1b/, 'No raw ESC byte in the log file');
    like($content, qr/transform:sleep 30/, 'The rest of the tag text is still preserved');

    Zepto::HangWatchdog::stop($wd);
};

done_testing;
