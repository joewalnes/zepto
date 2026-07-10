#!/usr/bin/env perl
# Tests for Zepto::AIHttp
#
# Covers the security-critical surface: curl config escaping (adversarial
# strings) and the argv-leak fix (the API key must never appear on the
# curl child's argv, env, or in any file). Spins a local plain-HTTP mock
# server (core Perl: IO::Socket::INET + fork) to drive real curl requests
# end-to-end.
use strict;
use warnings;
use Test::More;
use IO::Socket::INET;
use POSIX qw(:sys_wait_h);
use Time::HiRes qw(sleep time);
use File::Temp qw(tempdir);
use lib 'lib';
use Zepto::AIHttp;

Zepto::AIHttp::_reset_curl_cache();

if (!Zepto::AIHttp::curl_available()) {
    plan skip_all => 'curl not found on PATH';
}

my $TMPDIR = tempdir(CLEANUP => 1);

# ============================================================================
# curl config string escaping (pure unit tests, no process spawning)
# ============================================================================
subtest 'escape_config_string: backslash' => sub {
    is(Zepto::AIHttp::escape_config_string('a\\b'), 'a\\\\b');
};
subtest 'escape_config_string: double quote' => sub {
    is(Zepto::AIHttp::escape_config_string('say "hi"'), 'say \\"hi\\"');
};
subtest 'escape_config_string: newline' => sub {
    is(Zepto::AIHttp::escape_config_string("line1\nline2"), 'line1\\nline2');
};
subtest 'escape_config_string: carriage return and tab' => sub {
    is(Zepto::AIHttp::escape_config_string("a\rb\tc"), 'a\\rb\\tc');
};
subtest 'escape_config_string: backslash immediately before a quote' => sub {
    # A naive escaper that does quote-then-backslash (wrong order) would
    # turn `\"` into `\\"` (unterminated) instead of `\\\"`.
    is(Zepto::AIHttp::escape_config_string('\\"'), '\\\\\\"');
};
subtest 'escape_config_string: unicode passes through untouched' => sub {
    my $s = "caf\x{e9} \x{1F600} \x{4e2d}\x{6587}";
    is(Zepto::AIHttp::escape_config_string($s), $s, 'non-ASCII is not mangled');
};
subtest 'escape_config_string: curly braces pass through untouched (only quotes escaped)' => sub {
    is(Zepto::AIHttp::escape_config_string('{"a":"b"}'), '{\\"a\\":\\"b\\"}');
};
subtest 'escape_config_string: empty and undef' => sub {
    is(Zepto::AIHttp::escape_config_string(''), '');
    is(Zepto::AIHttp::escape_config_string(undef), '');
};

# ============================================================================
# extract_status
# ============================================================================
subtest 'extract_status splits body from the appended write-out marker' => sub {
    my ($body, $status) = Zepto::AIHttp::extract_status("hello world\nZEPTO_AI_HTTP_STATUS:200\n");
    is($body, "hello world");
    is($status, '200');
};
subtest 'extract_status returns undef status when marker missing' => sub {
    my ($body, $status) = Zepto::AIHttp::extract_status("connection refused");
    is($body, "connection refused");
    is($status, undef);
};
subtest 'extract_status handles a JSON body containing the literal marker text' => sub {
    # Only a marker anchored at end-of-string (preceded by newline) counts;
    # a JSON string value that happens to contain similar text must not be
    # mistaken for the real marker if it isn't in the anchored position.
    my ($body, $status) = Zepto::AIHttp::extract_status(qq({"x":"not ZEPTO_AI_HTTP_STATUS:1 a marker"}\nZEPTO_AI_HTTP_STATUS:404\n));
    is($status, '404');
    like($body, qr/not ZEPTO_AI_HTTP_STATUS:1 a marker/, 'embedded lookalike text preserved in body');
};

# ============================================================================
# Mock HTTP server helpers
# ============================================================================

# Starts a one-shot plain-HTTP mock server on 127.0.0.1. Forks a child that
# accepts exactly one connection, reads the request, waits $delay seconds
# (so the parent has a window to inspect the curl child's argv while the
# request is still in flight), writes the captured request to
# $capture_file, then responds with $status/$resp_body and exits.
# Returns ($port, $server_pid).
sub start_mock_server {
    my (%opts) = @_;
    my $delay        = $opts{delay} // 0.4;
    my $status       = $opts{status} // '200 OK';
    my $resp_body    = $opts{resp_body} // '{}';
    my $capture_file = $opts{capture_file};

    my $listener = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto     => 'tcp',
        Listen    => 5,
        ReuseAddr => 1,
    ) or die "Cannot create mock server socket: $!";
    my $port = $listener->sockport();

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        # --- Child: the mock server ---
        my $client = $listener->accept();
        if (!$client) { POSIX::_exit(1); }
        $client->autoflush(1);

        local $/ = "\r\n";
        my $request_line = <$client> // '';
        my %headers;
        while (my $line = <$client>) {
            $line =~ s/\r?\n$//;
            last if $line eq '';
            if ($line =~ /^([^:]+):\s*(.*)$/) {
                $headers{lc $1} = $2;
            }
        }
        my $body = '';
        my $len = $headers{'content-length'} // 0;
        if ($len > 0) {
            read($client, $body, $len);
        }

        if ($capture_file) {
            open(my $fh, '>:raw', $capture_file) or POSIX::_exit(1);
            print $fh "REQUEST_LINE:$request_line";
            for my $k (sort keys %headers) {
                print $fh "HEADER:$k: $headers{$k}\n";
            }
            print $fh "BODY_LEN:" . length($body) . "\n";
            print $fh "BODY_START\n$body\nBODY_END\n";
            close $fh;
        }

        sleep($delay);

        print $client "HTTP/1.1 $status\r\n";
        print $client "Content-Type: application/json\r\n";
        print $client "Content-Length: " . length($resp_body) . "\r\n";
        print $client "Connection: close\r\n\r\n";
        print $client $resp_body;
        close $client;
        POSIX::_exit(0);
    }

    close $listener;
    return ($port, $pid);
}

sub read_captured_request {
    my ($capture_file, $timeout) = @_;
    $timeout //= 3;
    my $deadline = time() + $timeout;
    while (!-s $capture_file && time() < $deadline) {
        sleep(0.02);
    }
    return '' unless -s $capture_file;
    open(my $fh, '<:raw', $capture_file) or return '';
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

# Drain a Zepto::AIHttp request handle to completion (bounded wait).
sub drain {
    my ($handle, $timeout) = @_;
    $timeout //= 5;
    my $buf = '';
    my $deadline = time() + $timeout;
    while (time() < $deadline) {
        my $state = Zepto::AIHttp::poll($handle, \$buf);
        if ($state eq 'done') {
            Zepto::AIHttp::finish($handle);
            return $buf;
        }
        sleep(0.02);
    }
    Zepto::AIHttp::kill_request($handle);
    return $buf;
}

# Read a process's argv (space-joined) via /proc (Linux) or `ps` (portable
# fallback). Returns undef if neither is available (caller should skip).
sub read_argv {
    my ($pid) = @_;
    if (-r "/proc/$pid/cmdline") {
        open(my $fh, '<:raw', "/proc/$pid/cmdline") or return undef;
        local $/;
        my $raw = <$fh>;
        close $fh;
        if (defined $raw && length $raw) {
            (my $joined = $raw) =~ s/\x00/ /g;
            return $joined;
        }
    }
    my $ps_out = `ps -o args= -p $pid 2>/dev/null`;
    chomp $ps_out;
    return length($ps_out) ? $ps_out : undef;
}

# ============================================================================
# End-to-end: POST request, header/body verification, argv-leak assertion
# ============================================================================
subtest 'POST request: headers and body arrive intact; key never on curl argv' => sub {
    my $capture_file = "$TMPDIR/capture_post.txt";
    my ($port, $server_pid) = start_mock_server(
        delay        => 0.5,
        resp_body    => '{"choices":[{"message":{"content":"ok"}}]}',
        capture_file => $capture_file,
    );

    my $SECRET_KEY = 'sk-VERY-SECRET-abc123XYZ';
    my $body = '{"model":"gpt-5-nano","messages":[{"role":"user","content":"hi"}]}';

    my $handle = Zepto::AIHttp::start_request(
        method  => 'POST',
        url     => "http://127.0.0.1:$port/chat/completions",
        headers => [
            ['Authorization', "Bearer $SECRET_KEY"],
            ['Content-Type', 'application/json'],
        ],
        body    => $body,
        timeout => 10,
    );
    ok($handle, 'start_request returned a handle') or return;
    ok($handle->{pid}, 'handle has curl child pid');

    # While the mock server is still sleeping (request in flight), inspect
    # the curl child's argv for the secret key.
    sleep(0.15);
    my $argv = read_argv($handle->{pid});
  SKIP: {
        skip 'cannot read child argv on this platform (no /proc, no ps)', 2 unless defined $argv;
        unlike($argv, qr/\Q$SECRET_KEY\E/, 'API key does NOT appear on curl child argv while in flight');
        like($argv, qr/--config/, 'curl invoked with --config (flags only on argv)');
    }

    my $raw = drain($handle, 5);
    waitpid($server_pid, 0);

    my ($resp_body, $status) = Zepto::AIHttp::extract_status($raw);
    is($status, '200', 'HTTP status extracted from write-out marker');
    like($resp_body, qr/"content":"ok"/, 'response body received');

    my $captured = read_captured_request($capture_file);
    like($captured, qr/HEADER:authorization: Bearer \Q$SECRET_KEY\E/i, 'server received Authorization header with the key');
    like($captured, qr/\Q$body\E/, 'server received the exact JSON body');
};

subtest 'GET request for model listing' => sub {
    my $capture_file = "$TMPDIR/capture_get.txt";
    my ($port, $server_pid) = start_mock_server(
        delay        => 0.05,
        resp_body    => '{"data":[{"id":"model-a"},{"id":"model-b"}]}',
        capture_file => $capture_file,
    );

    my $handle = Zepto::AIHttp::start_request(
        method  => 'GET',
        url     => "http://127.0.0.1:$port/models",
        headers => [['Authorization', 'Bearer test-key']],
        timeout => 10,
    );
    ok($handle, 'GET request started');
    my $raw = drain($handle, 5);
    waitpid($server_pid, 0);
    my ($body, $status) = Zepto::AIHttp::extract_status($raw);
    is($status, '200');
    like($body, qr/model-a/);

    my $captured = read_captured_request($capture_file);
    like($captured, qr/^REQUEST_LINE:GET /, 'server saw a GET request');
};

subtest 'Auth failure surfaces a distinguishable HTTP status' => sub {
    my ($port, $server_pid) = start_mock_server(
        delay     => 0.05,
        status    => '401 Unauthorized',
        resp_body => '{"error":{"message":"Invalid API key"}}',
    );
    my $handle = Zepto::AIHttp::start_request(
        method => 'GET', url => "http://127.0.0.1:$port/models", timeout => 10,
    );
    my $raw = drain($handle, 5);
    waitpid($server_pid, 0);
    my ($body, $status) = Zepto::AIHttp::extract_status($raw);
    is($status, '401', 'auth error distinguishable from network error via HTTP status');
    like($body, qr/Invalid API key/);
};

subtest 'Connection failure (nothing listening) is distinguishable from an HTTP error' => sub {
    # Port 1 is a privileged port almost certainly not listening as a
    # plain-HTTP server we can connect to as a non-root user in test envs.
    # curl's convention for "never got a response" is %{http_code} == 000.
    my $handle = Zepto::AIHttp::start_request(
        method => 'GET', url => 'http://127.0.0.1:1/models', timeout => 3,
    );
    ok($handle, 'handle created even though nothing is listening');
    my $raw = drain($handle, 5);
    my ($body, $status) = Zepto::AIHttp::extract_status($raw);
    ok(Zepto::AIHttp::is_network_error($status), "status '" . ($status // 'undef') . "' recognized as a network error, not an HTTP error");
};

subtest 'is_network_error distinguishes network failure from real HTTP statuses' => sub {
    ok(Zepto::AIHttp::is_network_error(undef), 'undef is a network error');
    ok(Zepto::AIHttp::is_network_error('000'), "'000' is a network error");
    ok(!Zepto::AIHttp::is_network_error('200'), "'200' is not a network error");
    ok(!Zepto::AIHttp::is_network_error('401'), "'401' is not a network error");
};

# ============================================================================
# Adversarial end-to-end: quotes, backslashes, newlines, unicode, braces
# ============================================================================
subtest 'Adversarial JSON body survives the curl config round-trip byte-for-byte' => sub {
    my $capture_file = "$TMPDIR/capture_adversarial.txt";
    my ($port, $server_pid) = start_mock_server(
        delay        => 0.05,
        resp_body    => '{"ok":true}',
        capture_file => $capture_file,
    );

    # Adversarial payload: embedded quotes, backslashes, a raw newline,
    # unicode, and curly braces that could be mistaken for JSON/config
    # structure if escaping were wrong.
    my $adversarial = qq({"model":"x","messages":[{"role":"user","content":"She said \\"hi\\" then \\\\wrote\\\\\nnext line \x{1F600} \x{4e2d}\x{6587} {nested} \\t tab"}]});

    my $handle = Zepto::AIHttp::start_request(
        method  => 'POST',
        url     => "http://127.0.0.1:$port/chat/completions",
        headers => [['Content-Type', 'application/json']],
        body    => $adversarial,
        timeout => 10,
    );
    ok($handle, 'adversarial request started');
    drain($handle, 5);
    waitpid($server_pid, 0);

    my $captured = read_captured_request($capture_file);
    like($captured, qr/BODY_LEN:(\d+)/, 'captured body length recorded');
    my ($declared_len) = $captured =~ /BODY_LEN:(\d+)/;
    my ($received_body) = $captured =~ /BODY_START\n(.*)\nBODY_END\n/s;
    is(length($received_body), $declared_len, 'Content-Length matches actual bytes received')
        or diag("expected len: $declared_len, got: " . length($received_body // ''));

    # utf8-encode the adversarial string the same way curl would have sent
    # it over the wire, for byte-accurate comparison.
    my $expected = $adversarial;
    utf8::encode($expected) if utf8::is_utf8($expected);
    is($received_body, $expected, 'server received the exact adversarial body, unmangled');
};

# ============================================================================
# curl availability detection
# ============================================================================
subtest 'curl_available caches its result' => sub {
    Zepto::AIHttp::_reset_curl_cache();
    my $first = Zepto::AIHttp::curl_available();
    ok(length($first), 'curl found');
    local $ENV{PATH} = '/nonexistent/path/that/does/not/exist';
    my $second = Zepto::AIHttp::curl_available();
    is($second, $first, 'cached result reused even after PATH changes');
    Zepto::AIHttp::_reset_curl_cache();
};

subtest 'curl_available returns empty string when curl is not on PATH' => sub {
    Zepto::AIHttp::_reset_curl_cache();
    local $ENV{PATH} = "$TMPDIR/empty-bin";
    mkdir "$TMPDIR/empty-bin" unless -d "$TMPDIR/empty-bin";
    is(Zepto::AIHttp::curl_available(), '', 'no curl found');
    Zepto::AIHttp::_reset_curl_cache();
};

subtest 'start_request returns undef when curl is unavailable' => sub {
    Zepto::AIHttp::_reset_curl_cache();
    local $ENV{PATH} = "$TMPDIR/empty-bin";
    my $handle = Zepto::AIHttp::start_request(method => 'GET', url => 'http://127.0.0.1:1/x');
    is($handle, undef, 'no handle when curl missing');
    Zepto::AIHttp::_reset_curl_cache();
};

done_testing();
