package Zepto::FileSearchEngine;
# =============================================================================
# FileSearchEngine: Cross-file search with async subprocess I/O
# =============================================================================
#
# Searches across files in the project tree using the best available backend:
#   1. git grep (if in a git repo)
#   2. rg (ripgrep, if installed)
#   3. grep (nearly always available)
#   4. Pure Perl fallback (File::Find + line-by-line scan)
#
# Results are streamed asynchronously via tick() called from the event loop.
# =============================================================================

use strict;
use warnings;
use IO::Select;
use Cwd ();
use File::Find ();
use File::Basename ();
use Time::HiRes qw(time);
use POSIX qw(WNOHANG);

use Zepto::Config;

use constant MAX_RESULTS => 1000;

# Wall-clock ceiling (seconds) for a single regex MATCH attempt, as opposed
# to _start_perl_search's ceiling for qr// compilation (see comment there).
# Mirrors FindEngine.pm's MATCH_ALARM_SECS / _match_with_alarm: compiling a
# pattern like `(a?){28}a{28}` is instant, but *matching* it against a run
# of 28 a's takes 15+ seconds of pure catastrophic backtracking (verified
# empirically). The compile-time alarm in _start_perl_search is cancelled
# before any match is ever attempted, so it provides zero protection here
# — this is a separate failure mode that needs its own guard around every
# match attempt (bugs.md P1 "FileSearchEngine.pm's 'Find in Files' regex
# search has no match-time ReDoS timeout, only compile-time").
use constant MATCH_ALARM_SECS => 1;

sub new {
    my ($class, %opts) = @_;
    return bless {
        # Backend detection
        _backend      => undef,   # 'git_grep', 'rg', 'grep', or 'perl'
        _detected     => 0,

        # Search state
        search_id     => 0,
        query         => '',
        scope_dir     => '',
        done          => 1,
        results       => [],
        result_count  => 0,
        _max_results  => MAX_RESULTS,

        # Search options
        case_sensitive => 0,
        use_regex      => 0,

        # Subprocess pipe state
        _pid          => undef,
        _pipe         => undef,
        _select       => undef,
        _buf          => '',

        # Pure Perl fallback state
        _perl_files   => [],      # Queue of files to search
        _perl_fh      => undef,   # Current file handle
        _perl_path    => undef,   # Current file path
        _perl_line_no => 0,       # Current line number
        _perl_query   => '',      # Query for matching (lowercased unless case_sensitive)

        # True if a match-time regex timeout (catastrophic backtracking)
        # occurred anywhere during the most recent search. Reset at the
        # start of every search(). Mirrors FindEngine.pm's
        # search_timed_out() flag/accessor.
        _search_timed_out => 0,
    }, $class;
}

# =============================================================================
# Backend Detection
# =============================================================================

sub detect_backend {
    my ($self, $root_path) = @_;
    return $self->{_backend} if $self->{_detected};

    $self->{_detected} = 1;

    # 1. Check for git repo
    if (-d "$root_path/.git") {
        my $ok = system('git', '--version') == 0;
        if ($ok) {
            $self->{_backend} = 'git_grep';
            return 'git_grep';
        }
    }

    # 2. Check for ripgrep
    {
        # Redirect stdout/stderr to /dev/null
        open my $devnull, '>', '/dev/null' or last;
        my $pid = fork();
        if (defined $pid && $pid == 0) {
            open STDOUT, '>&', $devnull;
            open STDERR, '>&', $devnull;
            exec('rg', '--version');
            exit 1;
        }
        close $devnull;
        if (defined $pid) {
            waitpid($pid, 0);
            if ($? == 0) {
                $self->{_backend} = 'rg';
                return 'rg';
            }
        }
    }

    # 3. Check for grep
    {
        open my $devnull, '>', '/dev/null' or last;
        my $pid = fork();
        if (defined $pid && $pid == 0) {
            open STDOUT, '>&', $devnull;
            open STDERR, '>&', $devnull;
            exec('grep', '--version');
            exit 1;
        }
        close $devnull;
        if (defined $pid) {
            waitpid($pid, 0);
            if ($? == 0) {
                $self->{_backend} = 'grep';
                return 'grep';
            }
        }
    }

    # 4. Pure Perl fallback
    $self->{_backend} = 'perl';
    return 'perl';
}

sub backend {
    my ($self) = @_;
    return $self->{_backend};
}

# =============================================================================
# Search Start
# =============================================================================

sub search {
    my ($self, $query, $scope_dir, %opts) = @_;

    # Reap any stale child processes from previous searches
    $self->_reap_stale();

    # Abort any in-flight search
    $self->abort() if !$self->{done};

    # Increment search id to invalidate stale reads
    $self->{search_id}++;

    # Store search options
    $self->{case_sensitive} = $opts{case_sensitive} // 0;
    $self->{use_regex}      = $opts{use_regex} // 0;
    $self->{_search_timed_out} = 0;

    # Reset results
    $self->{results}      = [];
    $self->{result_count} = 0;
    $self->{query}        = $query;
    $self->{scope_dir}    = $scope_dir;
    $self->{_buf}         = '';

    # Skip search for short queries
    if (!defined $query || length($query) < 2) {
        $self->{done} = 1;
        return;
    }

    # Validate scope directory
    if (!defined $scope_dir || !-d $scope_dir) {
        $self->{done} = 1;
        return;
    }

    $self->{done} = 0;

    my $backend = $self->{_backend} // 'perl';

    if ($backend eq 'perl') {
        $self->_start_perl_search($query, $scope_dir);
    } else {
        $self->_start_subprocess_search($query, $scope_dir, $backend);
    }
}

sub _start_subprocess_search {
    my ($self, $query, $scope_dir, $backend) = @_;

    # Build dynamic flags based on search options
    my $case_flag = $self->{case_sensitive} ? () : '-i';
    my $literal_flag = $self->{use_regex} ? '-E' : '-F';
    # rg uses -F for literal but defaults to regex when -F is omitted
    my $rg_literal_flag = $self->{use_regex} ? () : '-F';

    my @cmd;
    if ($backend eq 'git_grep') {
        @cmd = ('git', '-C', $scope_dir, 'grep',
                '-n', '--color=never', '-I');
        push @cmd, '-i' unless $self->{case_sensitive};
        push @cmd, $self->{use_regex} ? '-E' : '-F';
        push @cmd, '-e', $query;
    }
    elsif ($backend eq 'rg') {
        @cmd = ('rg', '--line-number', '--color=never', '--no-heading',
                '--with-filename');
        push @cmd, '-i' unless $self->{case_sensitive};
        push @cmd, '-F' unless $self->{use_regex};
        for my $dir (Zepto::Config::skip_directories()) {
            push @cmd, '--glob', "!$dir";
        }
        push @cmd, '-e', $query, $scope_dir;
    }
    elsif ($backend eq 'grep') {
        @cmd = ('grep', '-rn', '--color=never', '-I');
        push @cmd, '-i' unless $self->{case_sensitive};
        push @cmd, $self->{use_regex} ? '-E' : '-F';
        for my $dir (Zepto::Config::skip_directories()) {
            push @cmd, "--exclude-dir=$dir";
        }
        push @cmd, '-e', $query, $scope_dir;
    }

    # Use pipe + fork + exec (not open '-|') so close() won't block on waitpid
    pipe(my $read_end, my $write_end) or do {
        $self->{done} = 1;
        return;
    };

    my $pid = fork();
    if (!defined $pid) {
        close($read_end);
        close($write_end);
        $self->{done} = 1;
        return;
    }

    if ($pid == 0) {
        # Child: redirect stdout to pipe, suppress stderr, exec search command
        close($read_end);
        open(STDOUT, '>&', $write_end) or exit(1);
        open(STDERR, '>', '/dev/null');
        close($write_end);
        exec(@cmd);
        exit(1);
    }

    # Parent: read from pipe
    close($write_end);

    $self->{_pid}    = $pid;
    $self->{_pipe}   = $read_end;
    $self->{_select} = IO::Select->new($read_end);
}

sub _start_perl_search {
    my ($self, $query, $scope_dir) = @_;

    # Discover files
    my @files;
    my %skip = Zepto::Config::skip_directories_hash();
    my $max_files = Zepto::Config::max_files();
    my $max_depth = Zepto::Config::max_depth();
    my $base_depth = scalar(File::Spec->splitdir($scope_dir));

    File::Find::find({
        wanted => sub {
            return if scalar(@files) >= $max_files;
            my $path = $File::Find::name;

            # Skip directories
            if (-d $_) {
                if ($skip{$_}) {
                    $File::Find::prune = 1;
                    return;
                }
                my $depth = scalar(File::Spec->splitdir($path)) - $base_depth;
                if ($depth > $max_depth) {
                    $File::Find::prune = 1;
                    return;
                }
                return;
            }

            # Skip binary files (heuristic: check extension)
            return if /\.(png|jpg|jpeg|gif|ico|bmp|woff|woff2|ttf|eot|zip|tar|gz|pdf|exe|dll|so|dylib|o|a|class|pyc|pyo)$/i;

            push @files, $path;
        },
        no_chdir => 1,
    }, $scope_dir);

    $self->{_perl_files}   = \@files;
    $self->{_perl_fh}      = undef;
    $self->{_perl_path}    = undef;
    $self->{_perl_line_no} = 0;
    $self->{_perl_query}   = $self->{case_sensitive} ? $query : lc($query);

    # Precompile regex if in regex mode
    if ($self->{use_regex}) {
        # Limit pattern length to mitigate ReDoS (matches FindEngine limit)
        if (length($query) > 1000) {
            $self->{done} = 1;
            return;
        }
        my $re = eval {
            local $SIG{ALRM} = sub { die "regex_timeout\n" };
            alarm(1);
            my $compiled = $self->{case_sensitive} ? qr/$query/ : qr/$query/i;
            alarm(0);
            $compiled;
        };
        alarm(0);  # Ensure alarm is cancelled even on exception
        if (!$re) {
            # Invalid regex — abort search
            $self->{done} = 1;
            return;
        }
        $self->{_perl_regex} = $re;
    } else {
        $self->{_perl_regex} = undef;
    }
}

# =============================================================================
# Tick-based Async Read
# =============================================================================

sub tick {
    my ($self, $max_ms) = @_;
    $max_ms //= 30;

    # Reap any stale child processes from previous searches
    $self->_reap_stale();

    return { done => 1, count => $self->{result_count}, capped => 0 }
        if $self->{done};

    # Check if results are capped
    if ($self->{result_count} >= $self->{_max_results}) {
        $self->_finish();
        return { done => 1, count => $self->{result_count}, capped => 1 };
    }

    my $backend = $self->{_backend} // 'perl';
    if ($backend eq 'perl') {
        return $self->_tick_perl($max_ms);
    } else {
        return $self->_tick_subprocess($max_ms);
    }
}

sub _tick_subprocess {
    my ($self, $max_ms) = @_;

    my $pipe = $self->{_pipe};
    my $sel  = $self->{_select};
    return { done => 1, count => 0, capped => 0 } unless $pipe && $sel;

    my $deadline = time() + ($max_ms / 1000);
    my $scope_dir = $self->{scope_dir};

    while (time() < $deadline) {
        # Wait for data with short timeout (5ms)
        my $remaining = $deadline - time();
        $remaining = 0.005 if $remaining > 0.005;
        last if $remaining <= 0;

        my @ready = $sel->can_read($remaining);
        last unless @ready;

        my $bytes = sysread($pipe, my $chunk, 4096);

        if (!defined $bytes) {
            # Read error — finish
            $self->_finish();
            return { done => 1, count => $self->{result_count}, capped => 0 };
        }

        if ($bytes == 0) {
            # EOF — process remaining buffer then finish
            $self->_parse_lines($scope_dir, 1);
            $self->_finish();
            return { done => 1, count => $self->{result_count}, capped => 0 };
        }

        $self->{_buf} .= $chunk;
        $self->_parse_lines($scope_dir, 0);

        # Check cap
        if ($self->{result_count} >= $self->{_max_results}) {
            $self->_finish();
            return { done => 1, count => $self->{result_count}, capped => 1 };
        }
    }

    return { done => 0, count => $self->{result_count}, capped => 0 };
}

sub _parse_lines {
    my ($self, $scope_dir, $flush) = @_;

    my $buf = \$self->{_buf};
    my $results = $self->{results};
    my $max = $self->{_max_results};
    my $backend = $self->{_backend};
    my $query = $self->{query};
    my $case_sensitive = $self->{case_sensitive};
    my $use_regex = $self->{use_regex};

    while ($$buf =~ s/^([^\n]*)\n//) {
        last if $self->{result_count} >= $max;

        my $line = $1;
        # Parse file:line_num:content
        if ($line =~ /^(.+?):(\d+):(.*)$/) {
            my ($file, $line_num, $content) = ($1, $2, $3);

            # Normalize path: strip scope_dir prefix for display
            # For git grep, paths are relative to the repo root
            my $display_path = $file;
            if ($backend ne 'git_grep') {
                my $prefix = $scope_dir;
                $prefix .= '/' unless $prefix =~ m{/$};
                if (index($display_path, $prefix) == 0) {
                    $display_path = substr($display_path, length($prefix));
                }
            }

            # Trim content for display
            my $leading = 0;
            if ($content =~ s/^(\s+)//) {
                $leading = length($1);
            }

            # Compute match position in trimmed content
            my ($match_col, $match_len) = $self->_find_match_in_content($content, $query, $leading);

            if (length($content) > 200) {
                $content = substr($content, 0, 200);
            }

            push @$results, {
                file         => $file,
                display_path => $display_path,
                line_num     => $line_num,
                content      => $content,
                match_col    => $match_col,
                match_len    => $match_len,
            };
            $self->{result_count}++;
        }
    }

    # If flushing, process any remaining partial line
    if ($flush && length($$buf)) {
        if ($$buf =~ /^(.+?):(\d+):(.*)$/) {
            my ($file, $line_num, $content) = ($1, $2, $3);
            my $display_path = $file;
            if ($backend ne 'git_grep') {
                my $prefix = $scope_dir;
                $prefix .= '/' unless $prefix =~ m{/$};
                if (index($display_path, $prefix) == 0) {
                    $display_path = substr($display_path, length($prefix));
                }
            }
            my $leading = 0;
            if ($content =~ s/^(\s+)//) {
                $leading = length($1);
            }
            my ($match_col, $match_len) = $self->_find_match_in_content($content, $query, $leading);
            if (length($content) > 200) {
                $content = substr($content, 0, 200);
            }
            push @$results, {
                file         => $file,
                display_path => $display_path,
                line_num     => $line_num,
                content      => $content,
                match_col    => $match_col,
                match_len    => $match_len,
            };
            $self->{result_count}++;
        }
        $$buf = '';
    }
}

sub _find_match_in_content {
    my ($self, $content, $query, $leading) = @_;
    my $match_col = -1;
    my $match_len = 0;

    if ($self->{use_regex}) {
        my $re = $self->{_perl_regex};
        if ($re) {
            # Guard the MATCH itself, not just compilation — see
            # MATCH_ALARM_SECS / _match_with_alarm above. $-[0]/$+[0] are
            # read INSIDE the coderef since they don't reliably survive
            # being read after eval{} returns.
            my ($timed_out, $matched, $m_start, $m_end) = $self->_match_with_alarm(sub {
                my $ok = ($content =~ $re);
                return $ok ? (1, $-[0], $+[0]) : (0);
            });
            if ($timed_out) {
                # Pathological pattern on this one piece of display text —
                # skip highlighting for it and keep going; don't abort the
                # whole search over a single unhighlightable result.
                $self->{_search_timed_out} = 1;
            } elsif ($matched) {
                $match_col = $m_start;
                $match_len = $m_end - $m_start;
            }
        }
    } else {
        my $content_cmp = $self->{case_sensitive} ? $content : lc($content);
        my $query_cmp   = $self->{case_sensitive} ? $query : lc($query);
        my $pos = index($content_cmp, $query_cmp);
        if ($pos >= 0) {
            $match_col = $pos;
            $match_len = length($query_cmp);
        }
    }

    return ($match_col, $match_len);
}

sub _tick_perl {
    my ($self, $max_ms) = @_;

    my $deadline = time() + ($max_ms / 1000);
    my $files    = $self->{_perl_files};
    my $query_lc = $self->{_perl_query};
    my $results  = $self->{results};
    my $max      = $self->{_max_results};
    my $scope_dir = $self->{scope_dir};

    while (time() < $deadline) {
        # If we have no open file, get next one
        if (!$self->{_perl_fh}) {
            if (!@$files) {
                # No more files
                $self->{done} = 1;
                return { done => 1, count => $self->{result_count}, capped => 0 };
            }
            my $path = shift @$files;
            if (open(my $fh, '<', $path)) {
                $self->{_perl_fh}      = $fh;
                $self->{_perl_path}    = $path;
                $self->{_perl_line_no} = 0;
            } else {
                next;  # Skip unreadable files
            }
        }

        # Read lines from current file
        my $fh = $self->{_perl_fh};
        my $use_regex = $self->{use_regex};
        my $perl_regex = $self->{_perl_regex};
        my $case_sensitive = $self->{case_sensitive};
        while (defined(my $line = <$fh>)) {
            $self->{_perl_line_no}++;
            chomp $line;

            my $matched = 0;
            my $match_col = -1;
            my $match_len = 0;
            if ($use_regex && $perl_regex) {
                # Guard the MATCH itself, not just compilation — see
                # MATCH_ALARM_SECS / _match_with_alarm above. The
                # deadline check at the bottom of this loop only runs
                # *between* completed line matches, so it can never
                # catch a single pathological match attempt that
                # doesn't return on its own (e.g. `(a?){28}a{28}`
                # against a long run of a's — verified to hang for
                # 15+ seconds with no per-match guard). $-[0]/$+[0]
                # are read INSIDE the coderef since they don't
                # reliably survive being read after eval{} returns.
                my ($timed_out, $re_matched, $m_start, $m_end) = $self->_match_with_alarm(sub {
                    my $ok = ($line =~ $perl_regex);
                    return $ok ? (1, $-[0], $+[0]) : (0);
                });
                if ($timed_out) {
                    # Pathological pattern against this one line — treat
                    # as no-match-on-this-line and keep scanning. Each
                    # line is different input, so (unlike a single /g
                    # loop re-attempting the same position) skipping
                    # forward makes progress rather than looping forever
                    # on the same doomed match.
                    $self->{_search_timed_out} = 1;
                } elsif ($re_matched) {
                    $matched = 1;
                    $match_col = $m_start;
                    $match_len = $m_end - $m_start;
                }
            } else {
                my $line_cmp = $case_sensitive ? $line : lc($line);
                my $pos = index($line_cmp, $query_lc);
                if ($pos >= 0) {
                    $matched = 1;
                    $match_col = $pos;
                    $match_len = length($query_lc);
                }
            }

            if ($matched) {
                my $display_path = $self->{_perl_path};
                my $prefix = $scope_dir;
                $prefix .= '/' unless $prefix =~ m{/$};
                if (index($display_path, $prefix) == 0) {
                    $display_path = substr($display_path, length($prefix));
                }

                my $content = $line;
                my $leading = 0;
                if ($content =~ s/^(\s+)//) {
                    $leading = length($1);
                }
                # Adjust match_col for stripped leading whitespace
                $match_col -= $leading if $match_col >= $leading;
                if (length($content) > 200) {
                    $content = substr($content, 0, 200);
                }

                push @$results, {
                    file         => $self->{_perl_path},
                    display_path => $display_path,
                    line_num     => $self->{_perl_line_no},
                    content      => $content,
                    match_col    => $match_col,
                    match_len    => $match_len,
                };
                $self->{result_count}++;

                if ($self->{result_count} >= $max) {
                    close $fh;
                    $self->{_perl_fh} = undef;
                    $self->{done} = 1;
                    return { done => 1, count => $self->{result_count}, capped => 1 };
                }
            }

            last if time() >= $deadline;
        }

        # If we've exhausted this file, close it
        if (eof($fh)) {
            close $fh;
            $self->{_perl_fh} = undef;
        }
    }

    return { done => 0, count => $self->{result_count}, capped => 0 };
}

# =============================================================================
# Cleanup
# =============================================================================

sub abort {
    my ($self) = @_;

    $self->_cleanup_subprocess();

    # Clean up Perl fallback state
    if ($self->{_perl_fh}) {
        close($self->{_perl_fh});
        $self->{_perl_fh} = undef;
    }

    $self->{done}    = 1;
    $self->{search_id}++;
}

sub _finish {
    my ($self) = @_;
    $self->_cleanup_subprocess();
    $self->{done}    = 1;
}

# Non-blocking subprocess cleanup: close pipe, signal child, reap with WNOHANG
sub _cleanup_subprocess {
    my ($self) = @_;

    if ($self->{_pipe}) {
        close($self->{_pipe});
        $self->{_pipe} = undef;
    }
    $self->{_select} = undef;
    $self->{_buf}    = '';

    if ($self->{_pid}) {
        kill('TERM', $self->{_pid});
        my $ret = waitpid($self->{_pid}, WNOHANG);
        if ($ret <= 0) {
            # Child not dead yet — stash for later reaping
            push @{$self->{_stale_pids} //= []}, $self->{_pid};
        }
        $self->{_pid} = undef;
    }
}

# Reap any stale child processes (non-blocking)
sub _reap_stale {
    my ($self) = @_;
    my $pids = $self->{_stale_pids} or return;
    @$pids = grep {
        my $ret = waitpid($_, WNOHANG);
        $ret <= 0;  # keep if not yet reaped
    } @$pids;
}

sub is_searching {
    my ($self) = @_;
    return !$self->{done};
}

# True if a match-time regex timeout (catastrophic backtracking) occurred
# during the most recent search — some lines/files may have been skipped
# rather than fully matched. Mirrors FindEngine.pm's search_timed_out().
sub search_timed_out {
    my ($self) = @_;
    return $self->{_search_timed_out} ? 1 : 0;
}

# Run a regex match attempt (passed as a coderef so this can guard both
# plain `=~` checks and more elaborate match/capture logic) under a
# match-time alarm. Returns ($timed_out, @result), where @result is
# exactly whatever $coderef->() returned (empty/omitted if timed out).
#
# This exists because the compile-time alarm in _start_perl_search only
# covers qr// compilation and is explicitly cancelled (alarm(0)) before
# any match is ever attempted — catastrophic backtracking happens at
# MATCH time, so that alarm provides zero protection against it. Mirrors
# FindEngine.pm's _match_with_alarm exactly (see FindEngine.pm:555-572
# for the full rationale and the $1/@-/@+ scoping pitfall it documents).
#
# IMPORTANT: $coderef MUST read $1/@-/@+ (or whatever match variables it
# needs) and return already-extracted plain values — NOT rely on the
# caller reading match variables after this sub returns. See
# FindEngine.pm's _match_with_alarm doc comment for why.
sub _match_with_alarm {
    my ($self, $coderef) = @_;

    my @result = eval {
        local $SIG{ALRM} = sub { die "regex_match_timeout\n" };
        alarm(MATCH_ALARM_SECS);
        my @r = $coderef->();
        alarm(0);
        @r;
    };
    alarm(0);  # Ensure alarm is cancelled even on exception

    if ($@) {
        die $@ unless $@ eq "regex_match_timeout\n";
        return (1);  # timed_out, no result
    }
    return (0, @result);
}

1;
