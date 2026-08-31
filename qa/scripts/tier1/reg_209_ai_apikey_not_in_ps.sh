#!/usr/bin/env bash
# QA-REG-209: The AI completion API key is never visible in `ps` output
# while a real completion request is in flight — see bugs.md P2 "AI API
# key passed as a curl command-line argument, visible to other local
# users via ps".
#
# The original bug: AIComplete.pm's _child_http_request() built curl's
# Authorization header directly into argv
# (`-H "Authorization: Bearer $api_key"`), which any local user could
# read via `ps aux` / `/proc/<pid>/cmdline` for the whole lifetime of the
# curl child process — and this fires on every AI completion request
# while typing. The fix writes the header to a short-lived, mode-0600
# temp file and passes it to curl via `-K`/`--config` instead.
#
# tests/ai_complete.t already covers the fork/exec/argv-construction
# logic directly (with a stub `curl`). This script instead drives the
# REAL, running editor end-to-end through the actual UI a user would
# use, against a real (local, mock) HTTP endpoint and a real curl
# subprocess, and inspects the live process table -- the exact attack
# surface the bug describes. Non-tautological: this script was run
# against the pre-fix code (curl invoked with -H "Authorization: Bearer
# $api_key" in argv) and failed both the "-K observed" check (never
# true -- no -K flag existed) and the "key never leaked" check (the raw
# key showed up in ps within the first poll iteration, every time).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-209: AI API key not exposed via ps during a real curl request"

FAKE_KEY="sk-test-qa-reg-209-$$-do-not-leak"

# --- Mock AI endpoint (Perl stdlib only -- no CPAN, no `nc` dependency) ---
# Binds an OS-assigned free port (never a hardcoded one -- avoids
# collisions with other concurrent QA runs), records the raw request it
# receives, then deliberately delays its response so this test has a
# reliable multi-second window to observe the live curl child via `ps`.
mock_server="$QA_TMPDIR/mock_ai_server.pl"
cat > "$mock_server" <<'PERL_EOF'
use strict;
use warnings;
use Socket;

my ($port_file, $received_file, $delay) = @ARGV;
die "usage: mock_ai_server.pl PORT_FILE RECEIVED_FILE DELAY\n"
    unless defined $port_file && defined $received_file;
$delay //= 2.0;

socket(my $sock, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";
setsockopt($sock, SOL_SOCKET, SO_REUSEADDR, pack('l', 1));
bind($sock, sockaddr_in(0, inet_aton('127.0.0.1'))) or die "bind: $!";
listen($sock, 1) or die "listen: $!";

my ($port) = sockaddr_in(getsockname($sock));
open(my $pf, '>', $port_file) or die "open port_file: $!";
print $pf $port;
close $pf;

accept(my $client, $sock) or die "accept: $!";

my $data = '';
my $tries = 0;
while ($data !~ /\r\n\r\n/ && $tries < 200) {
    my $buf;
    my $n = sysread($client, $buf, 65536);
    last unless $n;
    $data .= $buf;
    $tries++;
}

open(my $rf, '>', $received_file) or die "open received_file: $!";
print $rf $data;
close $rf;

# Deliberate delay: keeps the curl child alive so the caller can observe
# it in `ps` before this responds.
sleep($delay);

print $client "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n";
print $client qq(data: {"choices":[{"delta":{"content":"OK"}}]}\n\n);
print $client "data: [DONE]\n\n";
close $client;
PERL_EOF

port_file="$QA_TMPDIR/mock_port.txt"
received_file="$QA_TMPDIR/mock_received.txt"
perl "$mock_server" "$port_file" "$received_file" 2.0 &
mock_pid=$!

# Chain our own mock-server cleanup onto the library's session/tmpdir
# cleanup (qa-helpers.sh already registered `trap qa_cleanup EXIT` at
# source time -- this replaces that registration with one that also
# reaps our background mock server, then still calls qa_cleanup).
trap 'kill "$mock_pid" 2>/dev/null || true; qa_cleanup' EXIT

# Wait for the mock server to bind and publish its port.
port_ready=0
for ((i = 0; i < 50; i++)); do
    if [[ -s "$port_file" ]]; then
        port_ready=1
        break
    fi
    sleep 0.1
done

if [[ "$port_ready" -eq 0 ]]; then
    qa_fail "mock AI server started" "port file never appeared"
    qa_summary
    exit $?
fi
mock_port=$(cat "$port_file")
qa_pass "mock AI server listening on 127.0.0.1:$mock_port"

# Pre-seed AI config directly in this test's isolated state dir --
# equivalent to a user having already completed "AI Completion: Setup"
# (that flow, including HTTPS enforcement, is covered end-to-end by
# QA-REG-210), pointed at our local mock instead of a real endpoint.
mkdir -p "$QA_STATE_DIR"
printf '{"ai_api_url":"http://127.0.0.1:%s","ai_model":"qa-reg-209-model"}' "$mock_port" \
    > "$QA_STATE_DIR/preferences.json"
printf '{"ai_api_key":"%s"}' "$FAKE_KEY" > "$QA_STATE_DIR/secrets.json"
chmod 600 "$QA_STATE_DIR/secrets.json"

file=$(qa_tmpfile_nl "reg209.txt" "hello world")
qa_start "$file"

# Discoverability: a configured key auto-enables AI Completion, and the
# toggle in the command palette reflects that.
qa_keys "ctrl-space"
qa_send "AI Completion" 0.3
qa_assert_expect '\[on\]' "AI Completion toggle shows [on] (auto-enabled by the configured key)"
qa_keys "escape"

# Trigger a real completion request against the real (mock) endpoint.
qa_keys "end"
qa_send "x"

# Poll the live process table while the mock server is deliberately
# stalling its response (curl is guaranteed to still be alive). Look for
# BOTH: positive proof the fixed code path ran (curl invoked with -K
# pointing at the .zepto-ai-curl-* temp file), and confirm the raw key
# / header text never appears anywhere in argv.
found_dashK=0
leaked_key=0
leaked_header=0
for ((i = 0; i < 60; i++)); do
    snapshot=$(ps aux 2>/dev/null || true)
    # Bash's own regex/substring matching, not `echo ... | grep` -- piping
    # ps's (sometimes large) output into `grep -q` lets grep close its
    # read end as soon as it finds a match, which can SIGPIPE the writer
    # and print a spurious "write error: Broken pipe" to stderr (a real
    # no-noise-in-test-output regression observed while writing this
    # script). Matching in-process avoids the pipe entirely.
    if [[ "$snapshot" =~ -K\ .*\.zepto-ai-curl- ]]; then
        found_dashK=1
    fi
    if [[ "$snapshot" == *"$FAKE_KEY"* ]]; then
        leaked_key=1
    fi
    if [[ "$snapshot" == *"Authorization"* ]]; then
        leaked_header=1
    fi
    sleep 0.1
done

if [[ "$found_dashK" -eq 1 ]]; then
    qa_pass "curl was observed invoked with -K <temp-config-file> (the fixed code path actually ran)"
else
    qa_fail "curl was observed invoked with -K <temp-config-file>" \
        "never observed in ps during the request window -- the request may not have fired at all"
fi

if [[ "$leaked_key" -eq 0 ]]; then
    qa_pass "Raw API key never appeared in 'ps aux' output during the request"
else
    qa_fail "Raw API key never appeared in 'ps aux' output during the request" \
        "key was visible in a ps snapshot -- this is the exact bug"
fi

if [[ "$leaked_header" -eq 0 ]]; then
    qa_pass "'Authorization' header text never appeared in 'ps aux' output"
else
    qa_fail "'Authorization' header text never appeared in 'ps aux' output" \
        "Authorization text was visible in a ps snapshot"
fi

# Let the mock server's delayed response land and close, then confirm it
# actually received the correct Authorization header -- proves the -K
# config-file mechanism still delivers the header correctly (this isn't
# "the feature silently stopped working").
sleep 2.5
qa_assert_file_contains "$received_file" "Authorization: Bearer $FAKE_KEY" \
    "Mock server received the correct Authorization header (delivered via -K, not argv)"

qa_keys "ctrl-q"
qa_summary
