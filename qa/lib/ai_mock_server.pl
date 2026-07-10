#!/usr/bin/env perl
# =============================================================================
# ai_mock_server.pl — minimal local HTTP mock for AI completion QA scripts
# =============================================================================
#
# A tiny plain-HTTP (no TLS) OpenAI-compatible mock server used by the
# ai_*.sh QA scripts to drive the AI Settings dialog / ghost-text completion
# against something real without any actual network access. Core Perl only
# (IO::Socket::INET + fork) — no CPAN.
#
# Usage: perl ai_mock_server.pl <port> [completion_text]
#
#   POST {base}/chat/completions -> 200 with {completion_text} as the
#     assistant message content, UNLESS the Authorization header is
#     exactly "Bearer wrong-key", in which case it returns 401 (used by
#     ai_002/ai_003 to test the auth-failure path).
#   GET  {base}/models           -> 200 with a fixed 3-model list.
#
# Prints "READY" to stdout once listening, so callers can poll for it
# instead of a fixed sleep.
# =============================================================================
use strict;
use warnings;
use IO::Socket::INET;
use POSIX ();

my $port = shift @ARGV or die "usage: $0 <port> [completion_text]\n";
my $completion_text = shift @ARGV // 'mock_completion_text';

my $listener = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => $port,
    Proto     => 'tcp',
    Listen    => 16,
    ReuseAddr => 1,
) or die "ai_mock_server: cannot listen on 127.0.0.1:$port: $!\n";

$| = 1;
print "READY\n";
$SIG{CHLD} = 'IGNORE';
$SIG{TERM} = sub { exit 0 };
$SIG{INT}  = sub { exit 0 };

while (my $client = $listener->accept()) {
    my $pid = fork();
    if (!defined $pid) { close $client; next; }
    if ($pid == 0) {
        close $listener;
        _handle($client, $completion_text);
        POSIX::_exit(0);
    }
    close $client;
}

sub _handle {
    my ($client, $completion_text) = @_;
    $client->autoflush(1);
    local $/ = "\r\n";
    my $req_line = <$client> // '';
    my %headers;
    while (my $line = <$client>) {
        $line =~ s/\r?\n$//;
        last if $line eq '';
        $headers{lc $1} = $2 if $line =~ /^([^:]+):\s*(.*)$/;
    }
    my $len = $headers{'content-length'} // 0;
    my $body = '';
    read($client, $body, $len) if $len > 0;

    my ($method, $path) = $req_line =~ /^(\S+)\s+(\S+)/;
    $path //= '';
    my $auth = $headers{'authorization'} // '';

    my ($status, $resp);
    if ($auth eq 'Bearer wrong-key') {
        $status = '401 Unauthorized';
        $resp   = '{"error":{"message":"Invalid API key provided"}}';
    }
    elsif ($path =~ m{/models}) {
        $status = '200 OK';
        $resp   = '{"data":[{"id":"mock-model-1"},{"id":"mock-model-2"},{"id":"mock-model-3"}]}';
    }
    elsif ($path =~ m{/chat/completions}) {
        $status = '200 OK';
        # JSON-escape the completion text minimally (no quotes/backslashes
        # expected from callers, but don't ship a footgun).
        (my $escaped = $completion_text) =~ s/(["\\])/\\$1/g;
        $resp = qq({"choices":[{"message":{"role":"assistant","content":"$escaped"}}]});
    }
    else {
        $status = '404 Not Found';
        $resp   = '{"error":{"message":"not found"}}';
    }

    print $client "HTTP/1.1 $status\r\nContent-Type: application/json\r\nContent-Length: "
        . length($resp) . "\r\nConnection: close\r\n\r\n$resp";
    close $client;
}
