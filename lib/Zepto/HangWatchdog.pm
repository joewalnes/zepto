package Zepto::HangWatchdog;
# =============================================================================
# HangWatchdog: detects a wedged main loop and writes diagnostics
# =============================================================================
#
# Design (no threads anywhere in this codebase — fork only):
#
#   - start() forks a child ("the watchdog") connected to the parent via a
#     pipe.
#   - The parent calls heartbeat($watchdog, $tag) frequently — once per
#     main-loop iteration, and before/after any operation expected to
#     block briefly (e.g. a shell transform, a clipboard command) — to
#     write a short tagged record down the pipe proving it's alive. $tag
#     identifies what the parent was doing at that moment, so the
#     diagnostic log can report the last known operation.
#   - The watchdog blocks in IO::Select::can_read($threshold) waiting for
#     heartbeat bytes. If none arrive within the threshold (default 10s),
#     it considers the parent wedged: it writes a diagnostic log file
#     under $log_dir and sends SIGUSR2 to the parent. It then keeps
#     watching (in case the parent recovers and later wedges again), but
#     won't re-fire for the SAME stretch of silence — only after another
#     heartbeat resumes and then stops again.
#   - The parent installs its own SIGUSR2 handler (see
#     Editor::_install_hang_signal_handler) to append a stack trace and
#     state summary to the SAME log file the watchdog just wrote. There's
#     no direct IPC payload on a plain signal, so the handler locates the
#     file via most_recent_log() (mtime) rather than needing the exact
#     name communicated explicitly — the SIGUSR2 delivery always follows
#     immediately after the watchdog's write, so this is reliable.
#   - The watchdog exits cleanly when the pipe reaches EOF (the parent
#     closed it deliberately via stop(), e.g. on shutdown) or when its
#     ppid changes (orphaned — the real parent died without cleaning up).
#   - stop() closes the pipe and reaps the watchdog without blocking
#     indefinitely (falls back to SIGKILL), so it never leaves a zombie.
# =============================================================================

use strict;
use warnings;
use POSIX qw(WNOHANG);
use IO::Select;
use Time::HiRes qw(time);
use File::Path ();

use constant HANG_THRESHOLD => 10;  # seconds without a heartbeat = hang

# Fork the watchdog. Returns a handle hashref on success, or undef if fork
# failed (caller should treat this as "watchdog disabled" and continue —
# never let watchdog setup failure block editor startup).
sub start {
    my (%opts) = @_;
    my $log_dir   = $opts{log_dir};
    my $threshold = $opts{threshold} // HANG_THRESHOLD;

    return undef unless pipe(my $read_fh, my $write_fh);

    my $parent_pid = $$;
    my $pid = fork();
    if (!defined $pid) {
        close($read_fh);
        close($write_fh);
        return undef;
    }

    if ($pid == 0) {
        # Watchdog child — never returns to caller code.
        close($write_fh);
        _watchdog_loop($read_fh, $parent_pid, $log_dir, $threshold);
        POSIX::_exit(0);
    }

    # Parent
    close($read_fh);
    $write_fh->autoflush(1);
    return { pid => $pid, write_fh => $write_fh, log_dir => $log_dir };
}

sub _watchdog_loop {
    my ($read_fh, $parent_pid, $log_dir, $threshold) = @_;

    my $sel = IO::Select->new($read_fh);
    my $last_tag = 'startup';
    my $already_fired = 0;

    while (1) {
        # Orphaned — the real parent died without going through stop() to
        # close the pipe (e.g. SIGKILL). Don't spin forever.
        last if getppid() != $parent_pid;

        my @ready = $sel->can_read($threshold);
        if (@ready) {
            my $buf;
            my $n = sysread($read_fh, $buf, 4096);
            last if !defined $n || $n == 0;  # EOF — parent shut down deliberately

            if ($buf =~ /([^\n]+)\n?[^\n]*\z/) {
                $last_tag = $1;
            }
            $already_fired = 0;  # heartbeat resumed — allow firing again later
            next;
        }

        # Timed out waiting for a heartbeat: the main loop appears wedged.
        next if $already_fired;  # already reported this stretch — don't spam
        $already_fired = 1;

        my $log_path = _write_hang_log($log_dir, $parent_pid, $last_tag);
        kill('USR2', $parent_pid) if $log_path;
    }
}

sub _write_hang_log {
    my ($log_dir, $pid, $last_tag) = @_;
    return undef unless $log_dir;

    eval { File::Path::make_path($log_dir) };
    return undef unless -d $log_dir;

    my @t = localtime(time());
    my $stamp = sprintf('%04d%02d%02d-%02d%02d%02d',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
    my $path = "$log_dir/hang-$stamp.log";

    return undef unless open(my $fh, '>>', $path);
    print $fh "=== Zepto hang detected (watchdog) ===\n";
    print $fh "pid: $pid\n";
    print $fh "time: " . scalar(localtime()) . "\n";
    print $fh "last heartbeat tag: " . _sanitize_tag($last_tag) . "\n";
    close($fh);
    return $path;
}

# The heartbeat tag can embed arbitrary user-typed text (e.g. a shell
# transform command, "transform:$cmd" — see Editor/Commands.pm). Strip
# control/escape characters before writing it to disk: this log file gets
# `cat`'d by a human debugging a hang, and per docs/SECURITY.md, terminal
# escape sequences from untrusted content must never reach a terminal
# unneutralized.
sub _sanitize_tag {
    my ($tag) = @_;
    return '' unless defined $tag;
    $tag =~ s/[\x00-\x1f\x7f]//g;
    return $tag;
}

# Called by the parent frequently to prove it's alive. Never blocks the
# caller for long — writes are tiny and the pipe is drained promptly by
# the watchdog, and any failure (watchdog gone, pipe broken) just disables
# future heartbeats rather than raising an error.
sub heartbeat {
    my ($watchdog, $tag) = @_;
    return unless $watchdog && $watchdog->{write_fh};
    $tag //= 'loop';
    local $SIG{PIPE} = 'IGNORE';
    my $ok = eval { print { $watchdog->{write_fh} } "$tag\n"; 1 };
    $watchdog->{write_fh} = undef unless $ok;
}

# Find the most recently written hang-*.log file in $log_dir. Used by the
# parent's SIGUSR2 handler to locate the file the watchdog just wrote.
sub most_recent_log {
    my ($log_dir) = @_;
    return undef unless $log_dir && -d $log_dir;
    opendir(my $dh, $log_dir) or return undef;
    my @logs = grep { /^hang-.*\.log$/ } readdir($dh);
    closedir($dh);
    return undef unless @logs;
    my @full = map { "$log_dir/$_" } @logs;
    my ($newest) = sort { (stat($b))[9] <=> (stat($a))[9] } @full;
    return $newest;
}

# Stop the watchdog cleanly: close the pipe (signals EOF so the child
# exits its select loop on its own) and reap it without blocking
# indefinitely, falling back to SIGKILL. Never leaves a zombie.
sub stop {
    my ($watchdog) = @_;
    return unless $watchdog;

    close($watchdog->{write_fh}) if $watchdog->{write_fh};
    my $pid = $watchdog->{pid};
    return unless $pid;

    my $deadline = time() + 1;
    my $reaped = 0;
    while (time() < $deadline) {
        my $ret = waitpid($pid, WNOHANG);
        if ($ret == $pid) { $reaped = 1; last; }
        select(undef, undef, undef, 0.05);
    }
    unless ($reaped) {
        kill('KILL', $pid);
        waitpid($pid, 0);
    }
}

1;
