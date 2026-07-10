#!/usr/bin/env perl
# =============================================================================
# AIComplete Test Suite
# =============================================================================
#
# Covers: config loading (opt-in, ships disabled), readiness gating (curl
# present, provider configured, key present unless not required), and the
# end-to-end JSON::PP response parsing path — including adversarial fixture
# responses (quotes, escapes, and a "delta" substring inside message
# content) that would have defeated the old regex-based SSE parser.
# =============================================================================
use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Temp qw(tempdir);
use IO::Socket::INET;
use POSIX qw(:sys_wait_h);
use Time::HiRes qw(sleep time);

use Zepto::AIComplete;
use Zepto::AIHttp;
use Zepto::Document;
use Zepto::View;
use Zepto::Highlighter;
use Zepto::Preferences;
use Zepto::StateStore;

Zepto::AIHttp::_reset_curl_cache();

sub make_doc {
    my ($content) = @_;
    my $doc = Zepto::Document->new();
    if ($doc->line_count() > 0) {
        my $total_len = $doc->length();
        $doc->delete(0, $total_len) if $total_len > 0;
    }
    $doc->insert(0, $content) if defined $content && length($content) > 0;
    return $doc;
}

# ============================================================================
# Config loading — ships disabled
# ============================================================================
subtest 'load_config populates fields but leaves the feature disabled' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);
    my $prefs = Zepto::Preferences->new(state_store => $store);
    $prefs->set('ai_provider', 'openai');
    $prefs->set('ai_api_url', 'https://api.openai.com/v1');
    $prefs->set('ai_model', 'gpt-5-nano');
    $store->put('secrets', { ai_api_key => 'sk-test' });

    my $ai = Zepto::AIComplete->new();
    $ai->load_config($prefs, $store);

    is($ai->provider_id(), 'openai');
    is($ai->api_url(), 'https://api.openai.com/v1');
    is($ai->model(), 'gpt-5-nano');
    ok(!$ai->is_enabled(), 'AI ships disabled even when fully configured - must be explicitly toggled on');
};

subtest 'fresh install: all AI prefs default to empty (no hardcoded provider)' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);
    my $prefs = Zepto::Preferences->new(state_store => $store);
    is($prefs->get('ai_provider'), '', 'ai_provider defaults empty');
    is($prefs->get('ai_api_url'), '', 'ai_api_url defaults empty');
    is($prefs->get('ai_model'), '', 'ai_model defaults empty');
};

# ============================================================================
# ready() gating
# ============================================================================
subtest 'ready() is false when unconfigured' => sub {
    my $ai = Zepto::AIComplete->new();
    ok(!$ai->ready(), 'not ready with no url/model/key');
    like($ai->not_ready_reason(), qr/not configured|curl/, 'reason given');
};

subtest 'ready() is false without curl on PATH' => sub {
    my $dir = tempdir(CLEANUP => 1);
    local $ENV{PATH} = "$dir/empty-bin";
    mkdir "$dir/empty-bin";
    Zepto::AIHttp::_reset_curl_cache();

    my $ai = Zepto::AIComplete->new();
    $ai->{provider_id} = 'openai';
    $ai->{api_url} = 'https://api.openai.com/v1';
    $ai->{model} = 'gpt-5-nano';
    $ai->{api_key} = 'sk-test';
    ok(!$ai->ready(), 'not ready when curl missing');
    is($ai->not_ready_reason(), 'curl not found on PATH');

    Zepto::AIHttp::_reset_curl_cache();
};

subtest 'ready() requires a key unless the provider needs none' => sub {
    plan skip_all => 'curl not found on PATH' unless Zepto::AIHttp::curl_available();

    my $ai = Zepto::AIComplete->new();
    $ai->{provider_id} = 'openai';
    $ai->{api_url} = 'https://api.openai.com/v1';
    $ai->{model} = 'gpt-5-nano';
    $ai->{api_key} = '';
    ok(!$ai->ready(), 'openai requires a key');

    $ai->{api_key} = 'sk-test';
    ok($ai->ready(), 'ready once a key is set');

    my $ollama = Zepto::AIComplete->new();
    $ollama->{provider_id} = 'ollama';
    $ollama->{api_url} = 'http://localhost:11434/v1';
    $ollama->{model} = 'llama3';
    $ollama->{api_key} = '';
    ok($ollama->ready(), 'ollama does not require a key');
};

# ============================================================================
# trigger()/check_trigger() respect enabled+ready gating
# ============================================================================
subtest 'trigger() is a no-op unless enabled and ready' => sub {
    my $ai = Zepto::AIComplete->new();
    my $doc = make_doc("hello\n");
    my $view = Zepto::View->new(document => $doc);
    $ai->trigger($doc, $view, undef);
    ok(!$ai->is_debouncing(), 'no debounce scheduled - feature is disabled');
};

# ============================================================================
# End-to-end: fire a real request against a local mock server, verify
# JSON::PP-based parsing (replacing the old regex SSE parser).
# ============================================================================

# Minimal one-shot plain-HTTP mock server (mirrors tests/ai_http.t's
# helper — deliberately not shared between test files per repo convention
# of self-contained .t files).
sub start_mock_server {
    my (%opts) = @_;
    my $resp_body = $opts{resp_body} // '{}';
    my $status    = $opts{status} // '200 OK';

    my $listener = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp',
        Listen => 5, ReuseAddr => 1,
    ) or die "mock server socket: $!";
    my $port = $listener->sockport();

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    if ($pid == 0) {
        my $client = $listener->accept();
        if ($client) {
            $client->autoflush(1);
            local $/ = "\r\n";
            my $req_line = <$client>;
            my %headers;
            while (my $line = <$client>) {
                $line =~ s/\r?\n$//;
                last if $line eq '';
                $headers{lc $1} = $2 if $line =~ /^([^:]+):\s*(.*)$/;
            }
            my $len = $headers{'content-length'} // 0;
            my $body = '';
            read($client, $body, $len) if $len > 0;
            print $client "HTTP/1.1 $status\r\nContent-Type: application/json\r\nContent-Length: "
                . length($resp_body) . "\r\nConnection: close\r\n\r\n$resp_body";
            close $client;
        }
        POSIX::_exit(0);
    }
    close $listener;
    return ($port, $pid);
}

sub run_ai_completion_against {
    my ($ai, $resp_body, $timeout) = @_;
    $timeout //= 5;
    my ($port, $server_pid) = start_mock_server(resp_body => $resp_body);
    $ai->{api_url} = "http://127.0.0.1:$port";
    $ai->{enabled} = 1;

    my $doc = make_doc("def foo():\n    pass\n");
    my $view = Zepto::View->new(document => $doc);
    $view->set_cursor(1, 8);
    my $hl = Zepto::Highlighter->new();

    $ai->trigger($doc, $view, $hl);
    ok($ai->is_debouncing(), 'debounce scheduled');

    # Force the debounce to have elapsed and fire.
    $ai->{_trigger_at} = time() - 1;
    ok($ai->check_trigger(), 'request fired');
    ok($ai->is_pending(), 'request pending');

    my $deadline = time() + $timeout;
    while (time() < $deadline) {
        last if $ai->poll();
        sleep(0.02);
    }
    waitpid($server_pid, 0);
    return $ai->result();
}

subtest 'End-to-end: plain completion text is parsed via JSON::PP' => sub {
    plan skip_all => 'curl not found on PATH' unless Zepto::AIHttp::curl_available();
    my $ai = Zepto::AIComplete->new();
    $ai->{provider_id} = 'custom';
    $ai->{model} = 'test-model';
    $ai->{api_key} = 'sk-test';

    my $resp = '{"choices":[{"message":{"role":"assistant","content":"return 42"}}]}';
    my $result = run_ai_completion_against($ai, $resp);
    is($result, 'return 42');
};

subtest 'End-to-end: adversarial content (quotes, escapes, embedded "delta") parses correctly' => sub {
    plan skip_all => 'curl not found on PATH' unless Zepto::AIHttp::curl_available();
    my $ai = Zepto::AIComplete->new();
    $ai->{provider_id} = 'custom';
    $ai->{model} = 'test-model';
    $ai->{api_key} = 'sk-test';

    # The OLD implementation regex-matched `"delta"\s*:\s*\{...\}` inside
    # the raw SSE buffer. A completion whose CONTENT itself contains the
    # literal text `"delta":{"content":"` would have been misparsed by
    # that regex (false match inside the string value). JSON::PP parses
    # this correctly because it understands string boundaries.
    my $tricky_content = 'x = "delta":{"content":"nested"}  # say \"hi\" \\ done';
    my $json = JSON::PP->new->utf8->encode({
        choices => [ { message => { content => $tricky_content } } ],
    });
    my $result = run_ai_completion_against($ai, $json);
    is($result, $tricky_content, 'adversarial content survives real JSON parsing intact');
};

subtest 'End-to-end: only the first line is kept, trimmed' => sub {
    plan skip_all => 'curl not found on PATH' unless Zepto::AIHttp::curl_available();
    my $ai = Zepto::AIComplete->new();
    $ai->{provider_id} = 'custom';
    $ai->{model} = 'test-model';
    $ai->{api_key} = 'sk-test';

    my $resp = JSON::PP->new->utf8->encode({
        choices => [ { message => { content => "  return 42  \nextra second line\nthird" } } ],
    });
    my $result = run_ai_completion_against($ai, $resp);
    is($result, 'return 42', 'trimmed, first line only');
};

subtest 'End-to-end: 401 auth error yields no ghost text (no crash)' => sub {
    plan skip_all => 'curl not found on PATH' unless Zepto::AIHttp::curl_available();
    my ($port, $server_pid) = start_mock_server(
        status => '401 Unauthorized',
        resp_body => '{"error":{"message":"Invalid API key"}}',
    );
    my $ai = Zepto::AIComplete->new();
    $ai->{provider_id} = 'custom';
    $ai->{model} = 'test-model';
    $ai->{api_key} = 'bad-key';
    $ai->{api_url} = "http://127.0.0.1:$port";
    $ai->{enabled} = 1;

    my $doc = make_doc("hello\n");
    my $view = Zepto::View->new(document => $doc);
    $ai->trigger($doc, $view, undef);
    $ai->{_trigger_at} = time() - 1;
    $ai->check_trigger();

    my $deadline = time() + 5;
    while (time() < $deadline) {
        last if $ai->poll();
        sleep(0.02);
    }
    waitpid($server_pid, 0);
    is($ai->result(), undef, 'no ghost text surfaced on auth error');
};

subtest 'cancel()/dismiss() reset state without crashing' => sub {
    my $ai = Zepto::AIComplete->new();
    $ai->cancel();
    $ai->dismiss();
    ok(1, 'no crash with no in-flight request');
    ok(!$ai->is_pending());
};

done_testing();
