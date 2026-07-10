package Zepto::VCS::Git;
# =============================================================================
# VCS::Git: Git version control integration
# =============================================================================
#
# Provides git-specific VCS operations:
#   - Detection: Find .git directory
#   - Content retrieval: Get file content at HEAD
#   - Tracking status: Check if file is tracked
#
# Uses the git command-line tool for operations. Gracefully handles missing git.
# All git commands use list-form exec (no shell interpretation) for safety.
# =============================================================================

use strict;
use warnings;
use utf8;
use parent 'Zepto::VCS::Provider';
use File::Basename qw(dirname);
use Cwd qw(abs_path getcwd);
use POSIX qw(WNOHANG);
# Time::HiRes's alarm() supports fractional seconds (core alarm() truncates
# to an integer, and alarm(0) means "cancel" — a fractional ZEPTO_GIT_TIMEOUT
# like 0.3, used to keep tests fast, would silently never fire with core
# alarm(), hanging forever on a wedged git process instead of timing out).
use Time::HiRes qw(time alarm);

# Hard timeout (seconds) for a single `git` invocation. VCS calls are
# reachable from the render path (status bar / gutter markers), so a
# wedged git process (e.g. a stale lock file prompting an interactive
# hang, or a network-mounted .git directory that's gone unresponsive)
# must not freeze the whole editor UI — see bugs.md P1 "cmd_transform
# open3 sequential-slurp can deadlock/hang UI indefinitely" (same
# blocking-pipe-I/O class of bug, different call site). Read at call time
# (not baked into a `use constant`) so ZEPTO_GIT_TIMEOUT can speed up
# tests that exercise the timeout path itself — see tests/vcs.t.
sub _git_timeout { $ENV{ZEPTO_GIT_TIMEOUT} || 3 }

# After a timeout, remember it briefly so a wedged git command isn't
# retried (and re-blocked-on) on every single render tick.
use constant GIT_FAILURE_CACHE_TTL => 5;

my %_git_timeout_until;  # "joined args" => time() until which we skip retrying

# Check if git is available (cached)
my $_git_available;

sub _git_available {
    return $_git_available if defined $_git_available;

    my ($output, $status) = _run_git('--version');
    $_git_available = ($status == 0) ? 1 : 0;

    return $_git_available;
}

# Register with the provider system
Zepto::VCS::Provider->register(__PACKAGE__);

# Wait for $pid to exit, up to $grace seconds, without ever blocking
# indefinitely; if it hasn't exited by then, kill it (and its process
# group — see setpgid in _run_git) and reap synchronously. $grace=0 means
# "skip straight to killing" (caller already knows this needs killing).
sub _bounded_reap {
    my ($pid, $grace) = @_;
    return unless $pid;
    $grace //= 0;

    if ($grace > 0) {
        my $deadline = time() + $grace;
        while (time() < $deadline) {
            my $ret = waitpid($pid, WNOHANG);
            return if $ret == $pid;
            select(undef, undef, undef, 0.05);
        }
    }

    kill('TERM', $pid);
    kill('TERM', -$pid);
    my $deadline = time() + 1;
    while (time() < $deadline) {
        my $ret = waitpid($pid, WNOHANG);
        return if $ret == $pid;
        select(undef, undef, undef, 0.05);
    }
    kill('KILL', $pid);
    kill('KILL', -$pid);
    waitpid($pid, 0);
}

# =============================================================================
# Safe git execution (no shell interpretation)
# =============================================================================

# Run a git command with list-form exec, suppressing stderr.
# Returns ($output, $exit_status) where exit_status is $? from waitpid.
# On timeout, returns (undef, -1) — same "spawn failed" sentinel already
# used elsewhere in this function — and every existing caller already
# guards on exit_status != 0 before touching $output, so this is safe.
sub _run_git {
    my (@args) = @_;

    my $cache_key = join("\x00", @args);
    if (my $until = $_git_timeout_until{$cache_key}) {
        if (time() < $until) {
            return (undef, -1);
        }
        delete $_git_timeout_until{$cache_key};
    }

    my $pid = open(my $fh, '-|');
    return ('', -1) unless defined $pid;
    if ($pid == 0) {
        # Own process group — git can spawn children of its own (pager,
        # credential helper, hooks); putting it in its own group lets a
        # timeout kill the whole tree, not just the immediate git process.
        eval { POSIX::setpgid(0, 0) };
        open(STDERR, '>', '/dev/null');
        exec('git', @args) or exit(127);
    }

    my $output;
    my $timed_out = 0;
    eval {
        local $SIG{ALRM} = sub { die "git_timeout\n" };
        alarm(_git_timeout());
        $output = do { local $/; <$fh> };
        alarm(0);
    };
    if ($@) {
        alarm(0);
        $timed_out = 1;
    }

    if ($timed_out) {
        # Reap BEFORE close() — close() on a pipe filehandle blocks
        # waiting for the child to exit (it does an internal waitpid), so
        # closing first would silently re-introduce the exact hang this
        # timeout exists to prevent. grace=0: we already know this needs
        # killing, no point waiting for a natural exit first.
        _bounded_reap($pid, 0);
        close($fh);
        $_git_timeout_until{$cache_key} = time() + GIT_FAILURE_CACHE_TTL;
        return (undef, -1);
    }

    # Bounded reap here too, not a bare close()/waitpid — reaching EOF on
    # the read does NOT guarantee git has actually exited yet (e.g. it
    # spawned a pager or credential helper that's still attached). A bare
    # close() would silently re-introduce the exact hang class this
    # timeout exists to prevent, just moved to the success path.
    _bounded_reap($pid, 2);
    # Capture $? BEFORE close($fh) — close() on this kind of filehandle
    # (opened via `open($fh, '-|')`) does its own internal waitpid, which
    # would fail (ECHILD, since _bounded_reap already reaped the child
    # above) and clobber $? with a bogus value.
    my $exit_status = $?;
    close($fh);
    return (defined $output ? $output : '', $exit_status);
}

# Instance helper: run git -C <repo_root> with given args
sub _git {
    my ($self, @args) = @_;
    return _run_git('-C', $self->{repo_root}, @args);
}

# =============================================================================
# Class Methods
# =============================================================================

sub new {
    my ($class, %opts) = @_;
    my $self = $class->SUPER::new(%opts);
    $self->{_content_cache} = {};  # Cache for HEAD content
    $self->{_head_mtime} = $self->_get_head_mtime();  # Track HEAD changes
    return $self;
}

# Detect if a file is in a git repository
# Returns a Git provider instance if found, undef otherwise
sub detect {
    my ($class, $file_path) = @_;
    return undef unless _git_available();
    return undef unless defined $file_path;

    # Handle non-existent files (new unsaved files)
    my $search_path = -e $file_path ? $file_path : dirname($file_path);
    return undef unless -e $search_path;

    my $repo_root = $class->SUPER::_find_repo_root($search_path, '.git');
    return undef unless defined $repo_root;

    return $class->new(repo_root => $repo_root);
}

# =============================================================================
# Instance Methods
# =============================================================================

sub name { 'git' }

# Check if a file is tracked by git
sub is_tracked {
    my ($self, $file_path) = @_;
    return 0 unless defined $file_path && -e $file_path;

    my $rel_path = $self->_relative_path($file_path);
    my ($output, $status) = $self->_git('ls-files', '--error-unmatch', $rel_path);

    return $status == 0;
}

# Get the content of a file at HEAD
sub get_head_content {
    my ($self, $file_path) = @_;
    return undef unless defined $file_path;

    my $rel_path = $self->_relative_path($file_path);

    # Check cache first
    if (exists $self->{_content_cache}{$rel_path}) {
        return $self->{_content_cache}{$rel_path};
    }

    # Use git show to get content at HEAD
    my ($content, $status) = $self->_git('show', "HEAD:$rel_path");

    if ($status != 0) {
        # File doesn't exist at HEAD (new file or not tracked)
        $self->{_content_cache}{$rel_path} = undef;
        return undef;
    }

    # Normalize line endings (git may return with original line endings)
    $content =~ s/\r\n/\n/g;

    # Strip trailing newline for consistency with Document.pm
    $content =~ s/\n$//;

    # Decode UTF-8
    utf8::decode($content);

    $self->{_content_cache}{$rel_path} = $content;
    return $content;
}

# Invalidate cache (call after save or external changes)
sub invalidate_cache {
    my ($self, $file_path) = @_;

    if (defined $file_path) {
        my $rel_path = $self->_relative_path($file_path);
        delete $self->{_content_cache}{$rel_path};
    } else {
        $self->{_content_cache} = {};
    }
}

# =============================================================================
# Utility
# =============================================================================

# Get mtime of the file that tracks current HEAD commit
# .git/HEAD may be a symbolic ref (ref: refs/heads/main) or detached (commit hash)
# For symbolic refs, we need to check the target ref file, not HEAD itself
sub _get_head_mtime {
    my ($self) = @_;
    my $git_dir = $self->{repo_root} . "/.git";
    my $head_file = "$git_dir/HEAD";

    # Read HEAD to see what it points to
    if (open my $fh, '<', $head_file) {
        my $content = <$fh>;
        close $fh;
        chomp $content if defined $content;

        # Check if symbolic ref (e.g., "ref: refs/heads/main")
        if (defined $content && $content =~ /^ref:\s*(.+)$/) {
            my $ref_path = "$git_dir/$1";
            # Return mtime of the actual ref file (e.g., .git/refs/heads/main)
            return (stat($ref_path))[9] // 0;
        }
    }

    # Detached HEAD or couldn't read - use HEAD file mtime
    return (stat($head_file))[9] // 0;
}

# Get worktree status for all tracked/untracked files
# Returns hashref: { relative_path => status_string }
sub get_worktree_status {
    my ($self) = @_;
    my ($output, $status) = $self->_git('status', '--porcelain');
    return {} if $status != 0;

    my %status;
    for my $line (split /\n/, $output) {
        my ($xy, $file) = ($line =~ /^(..) (.+)$/);
        next unless defined $file;
        # Strip quotes from filenames with special chars
        $file =~ s/^"(.+)"$/$1/;
        my $idx = substr($xy, 0, 1);
        my $wt  = substr($xy, 1, 1);

        if    ($wt eq '?' || $idx eq '?')        { $status{$file} = 'untracked'; }
        elsif ($wt eq 'M' || $wt eq 'D')         { $status{$file} = 'modified'; }
        elsif ($idx eq 'A')                       { $status{$file} = 'added'; }
        elsif ($idx eq 'M' || $idx eq 'R')        { $status{$file} = 'staged'; }
    }
    return \%status;
}

# Check if HEAD has changed since last check
# Returns true if changed, and updates stored mtime
sub head_changed {
    my ($self) = @_;
    my $current_mtime = $self->_get_head_mtime();
    if ($current_mtime != $self->{_head_mtime}) {
        $self->{_head_mtime} = $current_mtime;
        return 1;
    }
    return 0;
}

1;
