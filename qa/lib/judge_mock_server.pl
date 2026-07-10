#!/usr/bin/env perl
# =============================================================================
# judge_mock_server.pl — minimal local HTTP mock for tier-2 LLM-judge wiring
# =============================================================================
#
# A tiny plain-HTTP (no TLS) mock that speaks BOTH the Anthropic Messages
# wire shape (POST /v1/messages) and the OpenAI-compatible chat-completions
# wire shape (POST /v1/chat/completions, also used by openrouter) so
# qa/lib/llm-judge.sh can be exercised against something real without any
# actual network access. Core Perl only (IO::Socket::INET + fork) — no CPAN.
# Follows the same shape as qa/lib/ai_mock_server.pl (deliberately NOT
# reusing/importing that file — see CLAUDE.md task constraints — this is a
# separate, judge-specific mock).
#
# Usage: perl judge_mock_server.pl <port> <behavior> [reason] [request_log]
#
#   behavior:
#     pass       -> 200, strict-JSON body {"pass":true,"reason":<reason>}
#     fail       -> 200, strict-JSON body {"pass":false,"reason":<reason>}
#     malformed  -> 200, body that is NOT valid JSON (prose reply)
#     unauth     -> 401 for every request regardless of path/headers
#     empty      -> 200 with an empty/unexpected-shape JSON body
#
# Provider wire shape is auto-detected from the REQUEST PATH:
#   /v1/messages          -> Anthropic shape: {"content":[{"type":"text","text":...}]}
#   /v1/chat/completions   -> OpenAI-compatible shape: {"choices":[{"message":{"content":...}}]}
#
# If request_log is given, every request appends ONE line to it:
#   path=<path> auth_header=<0|1> bearer=<0|1> anthropic_version=<0|1> key_len=<N>
# The actual header VALUES (including any key) are never written to the
# log — only presence/length — so tests can assert "a key was sent" and
# "it never appears in any artifact" without contradicting each other.
#
# Prints "READY" to stdout once listening, so callers can poll for it
# instead of a fixed sleep.
# =============================================================================
use strict;
use warnings;
use IO::Socket::INET;
use POSIX ();

my $port        = shift @ARGV or die "usage: $0 <port> <behavior> [reason] [request_log] [delay_sec]\n";
my $behavior     = shift @ARGV // 'pass';
my $reason       = shift @ARGV // 'criteria met';
my $request_log  = shift @ARGV // '';
my $delay_sec    = shift @ARGV // 0;

my $listener = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => $port,
    Proto     => 'tcp',
    Listen    => 16,
    ReuseAddr => 1,
) or die "judge_mock_server: cannot listen on 127.0.0.1:$port: $!\n";

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
        _handle($client);
        POSIX::_exit(0);
    }
    close $client;
}

sub _handle {
    my ($client) = @_;
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

    if ($request_log) {
        my $auth_header      = exists $headers{'x-api-key'} ? 1 : 0;
        my $bearer            = ($headers{'authorization'} // '') =~ /^Bearer\s+\S+/ ? 1 : 0;
        my $anthropic_version = exists $headers{'anthropic-version'} ? 1 : 0;
        my $key_len = 0;
        if ($auth_header) { $key_len = length($headers{'x-api-key'}); }
        elsif ($bearer)   { ($key_len = length($1)) if $headers{'authorization'} =~ /^Bearer\s+(\S+)/; }
        my $model = ($body =~ /"model"\s*:\s*"([^"]*)"/) ? $1 : '';
        if (open my $fh, '>>', $request_log) {
            print $fh "path=$path auth_header=$auth_header bearer=$bearer anthropic_version=$anthropic_version key_len=$key_len model=$model\n";
            close $fh;
        }
    }

    # Artificial delay BEFORE sending the response — lets a caller snapshot
    # `ps` output while curl/the transport is still waiting on us, to
    # assert the key never appeared on any process's argv during the call
    # (see qa/scripts/tier1/judge_001_wiring.sh).
    select(undef, undef, undef, $delay_sec) if $delay_sec > 0;

    my ($status, $resp);

    if ($behavior eq 'unauth') {
        $status = '401 Unauthorized';
        $resp   = '{"error":{"message":"Invalid API key provided"}}';
    }
    elsif ($path =~ m{/v1/messages} || $path =~ m{/v1/chat/completions}) {
        my $is_anthropic = ($path =~ m{/v1/messages});
        my $text;
        if ($behavior eq 'pass') {
            $text = _json_escape(qq({"pass": true, "reason": "$reason"}));
        }
        elsif ($behavior eq 'fail') {
            $text = _json_escape(qq({"pass": false, "reason": "$reason"}));
        }
        elsif ($behavior eq 'malformed') {
            $text = _json_escape("Sure! Looking at the screenshot, I think this generally looks fine.");
        }
        else {
            $text = _json_escape('{}');
        }

        $status = '200 OK';
        if ($is_anthropic) {
            $resp = qq({"content":[{"type":"text","text":"$text"}]});
        } else {
            $resp = qq({"choices":[{"message":{"role":"assistant","content":"$text"}}]});
        }
    }
    else {
        $status = '404 Not Found';
        $resp   = '{"error":{"message":"not found"}}';
    }

    print $client "HTTP/1.1 $status\r\nContent-Type: application/json\r\nContent-Length: "
        . length($resp) . "\r\nConnection: close\r\n\r\n$resp";
    close $client;
}

sub _json_escape {
    my ($s) = @_;
    $s =~ s/(["\\])/\\$1/g;
    return $s;
}
