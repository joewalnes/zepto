package Zepto::AIHttp;
# =============================================================================
# AIHttp: Secure async HTTP transport for the AI completion feature
# =============================================================================
#
# The ONLY way Zepto talks to the network. curl only (never wget). This
# module exists to guarantee one thing above all else:
#
#   The API key and request body NEVER appear on argv, in the child's
#   environment, or in any file on disk.
#
# How: fork a child that execs `curl -sS --config -` — argv contains only
# flags, no URL, no secrets. The parent writes a curl config document (url,
# headers, body) to the child's stdin via a pipe. `ps` or /proc/<pid>/cmdline
# on the child can never reveal the key.
#
# The response (including our appended HTTP status marker, see
# extract_status) is read back from the child's stdout by the CALLER's
# non-blocking poll loop — this module never blocks waiting for a response;
# it only hands back a pollable handle.
# =============================================================================

use strict;
use warnings;
use POSIX qw(:sys_wait_h EAGAIN EWOULDBLOCK);
use IO::Select;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use constant _STATUS_MARKER => 'ZEPTO_AI_HTTP_STATUS:';

# curl path is detected once and cached for the life of the process.
my $CURL_PATH;

# Returns the absolute path to curl, or '' if not found on PATH.
sub curl_available {
    return $CURL_PATH if defined $CURL_PATH;
    for my $dir (split /:/, $ENV{PATH} // '') {
        next unless length $dir;
        my $candidate = "$dir/curl";
        if (-x $candidate && !-d $candidate) {
            $CURL_PATH = $candidate;
            return $CURL_PATH;
        }
    }
    $CURL_PATH = '';
    return $CURL_PATH;
}

# Test-only: clear the cached curl detection (e.g. after mutating PATH).
sub _reset_curl_cache { $CURL_PATH = undef; }

# =============================================================================
# curl --config escaping
# =============================================================================
#
# curl's -K/--config file format: `key = "value"` (or bare `key` for flags).
# Quoted string values use the SAME escape sequences as curl's URL/option
# parser: \\  \"  \t  \n  \r  \v.  A literal newline embedded in the value
# MUST be escaped to the two-character sequence backslash-n — an unescaped
# raw newline would terminate the config line early and corrupt the request
# (or, worse, get interpreted as a second config directive).
#
# This is the single most security-sensitive piece of this feature: if this
# escaping is wrong, adversarial content in the AI context (e.g. a source
# file containing a quote+newline sequence crafted to look like a config
# directive) could inject additional curl config directives. Covered by an
# adversarial unit test suite in tests/ai_http.t.
sub _escape_config_string {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/\\/\\\\/g;   # backslash first, or later substitutions double-escape
    $s =~ s/"/\\"/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    return $s;
}

# Test-exposed alias (kept private-by-convention, but the unit test suite
# needs direct access to verify the escaping rules in isolation).
sub escape_config_string { return _escape_config_string($_[0]); }

sub _config_line {
    my ($key, $value) = @_;
    return qq{$key = "} . _escape_config_string($value) . qq{"\n};
}

# =============================================================================
# Request execution
# =============================================================================

# Start an async HTTP request via curl. Returns a handle hashref, or undef
# if curl isn't available or fork/pipe failed. Never blocks the caller for
# longer than it takes to hand a small (context is length-capped by
# callers) config document to a pipe — see the non-blocking write loop
# below, bounded to a fixed number of attempts so a stalled child can never
# wedge the editor's event loop.
#
# %opts:
#   method  => 'GET' | 'POST'
#   url     => full URL
#   headers => [ [name, value], ... ]
#   body    => JSON string (POST only; omit for GET)
#   timeout => seconds (curl --max-time)
sub start_request {
    my (%opts) = @_;
    my $curl = curl_available();
    return undef unless $curl;
    return undef unless $opts{url};

    my $timeout = $opts{timeout} || 10;
    my $method  = uc($opts{method} || 'GET');

    my $config = '';
    $config .= _config_line('url', $opts{url});
    $config .= _config_line('request', $method);
    $config .= "silent\n";
    $config .= "show-error\n";
    $config .= _config_line('max-time', $timeout);
    # Append an unambiguous status marker after the body so the caller can
    # split body vs. HTTP status without needing curl's exit code to carry
    # that information (curl exits 0 even on 4xx/5xx unless -f is used).
    $config .= _config_line('write-out', "\n" . _STATUS_MARKER . "%{http_code}\n");
    for my $h (@{ $opts{headers} || [] }) {
        $config .= _config_line('header', "$h->[0]: $h->[1]");
    }
    if (defined $opts{body} && length($opts{body})) {
        $config .= _config_line('data', $opts{body});
    }

    pipe(my $out_read,  my $out_write) or return undef;
    pipe(my $cfg_read,  my $cfg_write) or do {
        close $out_read; close $out_write;
        return undef;
    };

    my $pid = fork();
    if (!defined $pid) {
        close $_ for ($out_read, $out_write, $cfg_read, $cfg_write);
        return undef;
    }

    if ($pid == 0) {
        # --- Child: exec curl with argv containing ONLY flags. No URL, no
        # key, no body on argv or in the environment — everything sensitive
        # travels over the config pipe on stdin. ---
        open(STDIN,  '<&', $cfg_read)  or POSIX::_exit(127);
        open(STDOUT, '>&', $out_write) or POSIX::_exit(127);
        open(STDERR, '>',  '/dev/null');
        close $out_read;
        close $out_write;
        close $cfg_read;
        close $cfg_write;
        exec($curl, '-sS', '--config', '-') or POSIX::_exit(127);
    }

    # --- Parent ---
    close $out_write;
    close $cfg_read;

    # The config document may contain non-ASCII bytes (AI context can
    # legitimately include unicode source text). Encode to UTF-8 bytes
    # before writing to the raw pipe — writing un-encoded wide characters
    # to a byte-oriented filehandle truncates/corrupts them.
    utf8::encode($config) if utf8::is_utf8($config);

    _set_nonblocking($cfg_write);
    my $to_write = $config;
    my $attempts = 0;
    while (length($to_write) && $attempts < 50) {
        my $n = syswrite($cfg_write, $to_write);
        if (defined $n) {
            substr($to_write, 0, $n, '');
        }
        elsif ($! == EAGAIN || $! == EWOULDBLOCK) {
            select(undef, undef, undef, 0.005);
        }
        else {
            last;   # write error — abandon; child sees a truncated config
        }
        $attempts++;
    }
    close $cfg_write;

    return {
        pid        => $pid,
        fh         => $out_read,
        select     => IO::Select->new($out_read),
        started_at => time(),
    };
}

sub _set_nonblocking {
    my ($fh) = @_;
    my $flags = fcntl($fh, F_GETFL, 0);
    return unless defined $flags;
    fcntl($fh, F_SETFL, $flags | O_NONBLOCK);
}

# Non-blocking poll: drains any currently-available bytes from the child
# into $$buf_ref. Returns 'done' once the child has closed its end (EOF),
# 'pending' if the request is still in flight.
sub poll {
    my ($handle, $buf_ref) = @_;
    return 'done' unless $handle && $handle->{select} && $handle->{fh};

    while ($handle->{select}->can_read(0)) {
        my $chunk;
        my $n = sysread($handle->{fh}, $chunk, 8192);
        if (!defined $n || $n == 0) {
            return 'done';
        }
        $$buf_ref .= $chunk;
    }
    return 'pending';
}

# True if the request has been running longer than $timeout seconds.
sub timed_out {
    my ($handle, $timeout) = @_;
    return 0 unless $handle;
    return (time() - ($handle->{started_at} // 0)) > $timeout;
}

# Clean up after a completed (EOF) request: close the pipe, reap the child.
sub finish {
    my ($handle) = @_;
    return unless $handle;
    close($handle->{fh}) if $handle->{fh};
    waitpid($handle->{pid}, WNOHANG) if $handle->{pid};
}

# Forcibly terminate an in-flight request (cancel / timeout).
sub kill_request {
    my ($handle) = @_;
    return unless $handle;
    if ($handle->{pid}) {
        kill('TERM', $handle->{pid});
        waitpid($handle->{pid}, WNOHANG);
    }
    close($handle->{fh}) if $handle->{fh};
}

# =============================================================================
# Response post-processing
# =============================================================================

# Split raw curl stdout (body + our appended write-out marker) into
# (body, http_status). http_status is undef if the marker is missing
# entirely (curl itself crashed/was killed before the transfer finished).
# curl's own convention for "no HTTP response was ever received" (DNS
# failure, connection refused, TLS failure, etc.) is to report the
# %{http_code} write-out variable as the literal string "000" — that
# case DOES have a marker, so callers must check both: use
# is_network_error() to test for "no usable HTTP response" rather than
# comparing $status to undef directly.
sub extract_status {
    my ($raw) = @_;
    $raw //= '';
    my $marker = _STATUS_MARKER;
    if ($raw =~ /\n\Q$marker\E(\d+)\n?\z/) {
        my $status = $1;
        my $body = substr($raw, 0, length($raw) - length($&));
        return ($body, $status);
    }
    return ($raw, undef);
}

# True if $status represents "no HTTP response was received" — either the
# write-out marker was missing entirely (undef) or curl reported its
# sentinel "000" (connect/DNS/TLS failure before any response).
sub is_network_error {
    my ($status) = @_;
    return 1 unless defined $status;
    return $status eq '000' ? 1 : 0;
}

1;
