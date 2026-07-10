#!/usr/bin/env perl
# Tests for Zepto::AIProviders
use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::AIProviders;
use JSON::PP ();

# ============================================================================
# Registry shape
# ============================================================================
subtest 'list() returns all documented providers in order' => sub {
    my @providers = Zepto::AIProviders::list();
    my @ids = map { $_->{id} } @providers;
    is_deeply(\@ids, [qw(openai anthropic openrouter opencode-zen opencode-go deepseek ollama gemini custom)],
        'provider ids match spec, in order');
};

subtest 'every provider has required fields' => sub {
    for my $p (Zepto::AIProviders::list()) {
        ok(defined $p->{id} && length $p->{id}, "$p->{id}: has id");
        ok(defined $p->{name} && length $p->{name}, "$p->{id}: has name");
        ok(defined $p->{base_url}, "$p->{id}: has base_url (may be empty for custom)");
        ok(defined $p->{auth}, "$p->{id}: has auth mode");
        ok(exists $p->{default_model}, "$p->{id}: has default_model key (may be blank)");
    }
};

subtest 'list() returns copies, not the live registry' => sub {
    my @a = Zepto::AIProviders::list();
    $a[0]->{name} = 'MUTATED';
    my @b = Zepto::AIProviders::list();
    isnt($b[0]->{name}, 'MUTATED', 'mutating a returned copy does not affect the registry');
};

subtest 'get() looks up by id' => sub {
    my $openai = Zepto::AIProviders::get('openai');
    is($openai->{base_url}, 'https://api.openai.com/v1', 'openai base_url');
    is($openai->{default_model}, 'gpt-5-nano', 'openai default model');

    my $anthropic = Zepto::AIProviders::get('anthropic');
    is($anthropic->{models_auth}, 'anthropic', 'anthropic has models_auth override');

    my $ollama = Zepto::AIProviders::get('ollama');
    is($ollama->{auth}, 'none', 'ollama requires no auth');
    is($ollama->{base_url}, 'http://localhost:11434/v1', 'ollama is localhost');

    is(Zepto::AIProviders::get('nonexistent'), undef, 'unknown id returns undef');
};

subtest 'providers with rotating rosters do not hardcode a default model' => sub {
    for my $id (qw(opencode-zen opencode-go ollama custom)) {
        my $p = Zepto::AIProviders::get($id);
        is($p->{default_model}, '', "$id: default_model left blank for live listing");
    }
};

# ============================================================================
# Wire adapter: completion request/response
# ============================================================================
subtest 'build_completion_request produces OpenAI-compatible shape' => sub {
    my $req = Zepto::AIProviders::build_completion_request(
        model => 'gpt-5-nano', system => 'sys', user => 'usr', max_tokens => 64,
    );
    is($req->{model}, 'gpt-5-nano');
    is(scalar(@{$req->{messages}}), 2);
    is($req->{messages}[0]{role}, 'system');
    is($req->{messages}[0]{content}, 'sys');
    is($req->{messages}[1]{role}, 'user');
    is($req->{messages}[1]{content}, 'usr');
    is($req->{max_tokens}, 64);
    is($req->{stream}, JSON::PP::false, 'stream is JSON false, not Perl 0');

    # Must round-trip through JSON::PP cleanly
    my $json = JSON::PP->new->canonical->encode($req);
    like($json, qr/"stream":false/, 'encodes as JSON false literal');
};

subtest 'parse_completion_response extracts message content' => sub {
    my $data = { choices => [ { message => { role => 'assistant', content => "hello\nworld" } } ] };
    is(Zepto::AIProviders::parse_completion_response($data), "hello\nworld");
};

subtest 'parse_completion_response handles adversarial content safely' => sub {
    my $tricky = qq{She said "hi"\\backslash\\nliteral};
    my $data = { choices => [ { message => { content => $tricky } } ] };
    is(Zepto::AIProviders::parse_completion_response($data), $tricky,
        'quotes/backslashes in content pass through untouched (no regex parsing)');
};

subtest 'parse_completion_response returns undef on malformed shapes' => sub {
    is(Zepto::AIProviders::parse_completion_response({}), undef, 'no choices');
    is(Zepto::AIProviders::parse_completion_response({ choices => [] }), undef, 'empty choices');
    is(Zepto::AIProviders::parse_completion_response({ choices => [{}] }), undef, 'no message');
    is(Zepto::AIProviders::parse_completion_response(undef), undef, 'undef input');
    is(Zepto::AIProviders::parse_completion_response("not a ref"), undef, 'scalar input');
};

# ============================================================================
# Wire adapter: model listing
# ============================================================================
subtest 'parse_models_response extracts model ids' => sub {
    my $data = { data => [ { id => 'gpt-5-nano', object => 'model' }, { id => 'gpt-5' } ] };
    my @ids = Zepto::AIProviders::parse_models_response($data);
    is_deeply(\@ids, ['gpt-5-nano', 'gpt-5']);
};

subtest 'parse_models_response tolerates malformed entries' => sub {
    my $data = { data => [ { id => 'ok' }, { no_id => 1 }, "not a hash", { id => '' } ] };
    my @ids = Zepto::AIProviders::parse_models_response($data);
    is_deeply(\@ids, ['ok'], 'skips entries without a usable id');
};

subtest 'parse_models_response returns empty list on malformed shapes' => sub {
    is_deeply([Zepto::AIProviders::parse_models_response({})], []);
    is_deeply([Zepto::AIProviders::parse_models_response(undef)], []);
};

subtest 'parse_error_message extracts OpenAI-style error' => sub {
    my $data = { error => { message => 'Invalid API key', type => 'invalid_request_error' } };
    is(Zepto::AIProviders::parse_error_message($data), 'Invalid API key');
};

subtest 'parse_error_message falls back gracefully' => sub {
    is(Zepto::AIProviders::parse_error_message({ error => 'plain string error' }), 'plain string error');
    is(Zepto::AIProviders::parse_error_message({ message => 'top level' }), 'top level');
    is(Zepto::AIProviders::parse_error_message({}), undef);
    is(Zepto::AIProviders::parse_error_message(undef), undef);
};

# ============================================================================
# Auth
# ============================================================================
subtest 'auth_headers builds Bearer header for bearer providers' => sub {
    my $p = Zepto::AIProviders::get('openai');
    my $headers = Zepto::AIProviders::auth_headers($p, 'sk-secret123');
    is_deeply($headers, [['Authorization', 'Bearer sk-secret123']]);
};

subtest 'auth_headers omits Authorization when key is blank' => sub {
    my $p = Zepto::AIProviders::get('openai');
    my $headers = Zepto::AIProviders::auth_headers($p, '');
    is_deeply($headers, [], 'no Authorization header without a key');
};

subtest 'auth_headers for ollama sends nothing even with a key set' => sub {
    my $p = Zepto::AIProviders::get('ollama');
    my $headers = Zepto::AIProviders::auth_headers($p, 'irrelevant');
    is_deeply($headers, [], 'ollama auth=>none never sends Authorization');
};

subtest 'auth_headers native_anthropic variant' => sub {
    my $p = Zepto::AIProviders::get('anthropic');
    my $headers = Zepto::AIProviders::auth_headers($p, 'sk-ant-1', 'native_anthropic');
    is_deeply($headers, [['x-api-key', 'sk-ant-1'], ['anthropic-version', '2023-06-01']]);
};

subtest 'models_auth_variants: only anthropic gets a fallback variant' => sub {
    is_deeply([Zepto::AIProviders::models_auth_variants(Zepto::AIProviders::get('anthropic'))],
        ['default', 'native_anthropic']);
    is_deeply([Zepto::AIProviders::models_auth_variants(Zepto::AIProviders::get('openai'))],
        ['default']);
};

done_testing();
