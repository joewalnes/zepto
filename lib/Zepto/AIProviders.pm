package Zepto::AIProviders;
# =============================================================================
# AIProviders: Registry of AI completion provider presets
# =============================================================================
#
# A data table of OpenAI-compatible API providers, plus the single wire
# adapter shared by all of them:
#
#   POST {base_url}/chat/completions  { model, messages, max_tokens, stream }
#   GET  {base_url}/models            -> { data: [ { id, ... }, ... ] }
#
# All JSON is parsed with JSON::PP (core) — no regex parsing anywhere.
#
# Some providers (Anthropic) expose /chat/completions in an OpenAI-compatible
# shape but require native headers (x-api-key + anthropic-version) for the
# /models listing endpoint. `models_auth => 'anthropic'` marks that case;
# callers should try the default Bearer auth first and fall back to the
# native variant on 401/403 (see models_auth_variants / auth_headers below).
# =============================================================================

use strict;
use warnings;
use JSON::PP ();

# Ordered list of provider presets. 'custom' is always last (user-supplied
# base URL). Model defaults marked '' are intentionally left blank — the
# roster for that provider rotates or is otherwise unsuitable to hardcode;
# the Settings dialog should populate the default from a live /models call.
my @PROVIDERS = (
    {
        id            => 'openai',
        name          => 'OpenAI',
        base_url      => 'https://api.openai.com/v1',
        auth          => 'bearer',
        default_model => 'gpt-5-nano',
    },
    {
        id            => 'anthropic',
        name          => 'Anthropic',
        base_url      => 'https://api.anthropic.com/v1',
        auth          => 'bearer',
        models_auth   => 'anthropic',   # /models may need native headers
        default_model => 'claude-haiku-4-5',
    },
    {
        id            => 'openrouter',
        name          => 'OpenRouter',
        base_url      => 'https://openrouter.ai/api/v1',
        auth          => 'bearer',
        default_model => 'anthropic/claude-haiku-4.5',  # verify slug via live listing
    },
    {
        id            => 'opencode-zen',
        name          => 'opencode zen',
        base_url      => 'https://opencode.ai/zen/v1',
        auth          => 'bearer',
        default_model => '',   # roster rotates — pick from live listing
    },
    {
        id            => 'opencode-go',
        name          => 'opencode go',
        base_url      => 'https://opencode.ai/zen/go/v1',
        auth          => 'bearer',
        default_model => '',   # roster rotates — pick from live listing
    },
    {
        id            => 'deepseek',
        name          => 'DeepSeek',
        base_url      => 'https://api.deepseek.com/v1',
        auth          => 'bearer',
        default_model => 'deepseek-chat',
    },
    {
        id            => 'ollama',
        name          => 'Ollama (local)',
        base_url      => 'http://localhost:11434/v1',
        auth          => 'none',   # no key required; plain HTTP to localhost
        default_model => '',       # pick from live listing (whatever's pulled)
    },
    {
        id            => 'gemini',
        name          => 'Gemini',
        base_url      => 'https://generativelanguage.googleapis.com/v1beta/openai',
        auth          => 'bearer',
        default_model => 'gemini-2.5-flash-lite',
    },
    {
        id            => 'custom',
        name          => 'Custom',
        base_url      => '',
        auth          => 'bearer',
        default_model => '',
    },
);

# Return the ordered list of provider presets (list of hashrefs, copies).
sub list {
    return map { { %$_ } } @PROVIDERS;
}

# Look up a single provider preset by id. Returns a copy, or undef.
sub get {
    my ($id) = @_;
    return undef unless defined $id;
    for my $p (@PROVIDERS) {
        return { %$p } if $p->{id} eq $id;
    }
    return undef;
}

# =============================================================================
# Wire adapter — shared by every provider
# =============================================================================

# Build the JSON body (as a Perl data structure) for a chat completion
# request. Caller JSON-encodes with JSON::PP.
sub build_completion_request {
    my (%args) = @_;
    return {
        model    => $args{model},
        messages => [
            { role => 'system', content => $args{system} // '' },
            { role => 'user',   content => $args{user}   // '' },
        ],
        max_tokens => $args{max_tokens} // 200,
        stream     => JSON::PP::false,
    };
}

# Parse a decoded /chat/completions response. Returns the completion text,
# or undef if the shape doesn't match what we expect (missing/malformed).
sub parse_completion_response {
    my ($data) = @_;
    return undef unless ref($data) eq 'HASH';
    my $choices = $data->{choices};
    return undef unless ref($choices) eq 'ARRAY' && @$choices;
    my $msg = $choices->[0]->{message};
    return undef unless ref($msg) eq 'HASH';
    my $content = $msg->{content};
    return undef unless defined $content && length($content);
    return $content;
}

# Parse a decoded /models response. Returns a list of model id strings
# (order preserved as returned by the API).
sub parse_models_response {
    my ($data) = @_;
    return () unless ref($data) eq 'HASH';
    my $list = $data->{data};
    return () unless ref($list) eq 'ARRAY';
    return map { $_->{id} }
           grep { ref($_) eq 'HASH' && defined $_->{id} && length($_->{id}) }
           @$list;
}

# Extract a human-readable error message from a decoded (or undecoded)
# error response body. OpenAI-compatible APIs return {"error":{"message":..}}
# but we tolerate anything.
sub parse_error_message {
    my ($data) = @_;
    return undef unless ref($data) eq 'HASH';
    my $err = $data->{error};
    if (ref($err) eq 'HASH' && defined $err->{message}) {
        return $err->{message};
    }
    return $err if defined $err && !ref($err);
    return $data->{message} if defined $data->{message} && !ref($data->{message});
    return undef;
}

# =============================================================================
# Auth
# =============================================================================

# Build the list of [header_name, header_value] pairs for a request.
# $variant: 'default' (Bearer, or none for auth=>'none') or 'native_anthropic'
# (x-api-key + anthropic-version — used as a fallback for Anthropic's
# /models endpoint when Bearer auth is rejected).
sub auth_headers {
    my ($provider, $key, $variant) = @_;
    $variant //= 'default';
    $key //= '';

    my @headers;
    if ($variant eq 'native_anthropic') {
        push @headers, ['x-api-key', $key] if length $key;
        push @headers, ['anthropic-version', '2023-06-01'];
    }
    elsif (($provider->{auth} // 'bearer') eq 'bearer' && length $key) {
        push @headers, ['Authorization', "Bearer $key"];
    }
    return \@headers;
}

# Which auth variants should be tried, in order, for the /models listing
# endpoint of this provider. Most providers only have one variant.
sub models_auth_variants {
    my ($provider) = @_;
    if (($provider->{models_auth} // '') eq 'anthropic') {
        return ('default', 'native_anthropic');
    }
    return ('default');
}

1;
