package Zepto::AIComplete;
# =============================================================================
# AIComplete: Async AI code completion via any OpenAI-compatible provider
# =============================================================================
#
# Uses Zepto::AIHttp (fork+curl+pipe) to make non-blocking HTTP requests to
# the user-configured provider (see Zepto::AIProviders). The editor event
# loop polls for results — this module never blocks.
#
# Features:
#   - Async: never blocks the editor event loop
#   - Debounced: waits for typing pause before requesting
#   - Cancellable: new keystrokes abort in-flight requests
#   - Rate-limited: max ~12 requests/minute
#   - Cost-aware: limits context and output tokens
#   - Opt-in: disabled by default; inert unless curl is present and the
#     provider is configured (key present, or provider requires none)
# =============================================================================

use strict;
use warnings;
use JSON::PP ();
use Zepto::AIHttp;
use Zepto::AIProviders;

# Context and output limits
use constant {
    PREFIX_LINES     => 30,     # Lines before cursor to send
    SUFFIX_LINES     => 5,      # Lines after cursor to send
    MAX_OUTPUT_TOKENS => 200,   # Max tokens in completion response
    DEBOUNCE_SEC     => 0.5,    # Seconds of inactivity before triggering
    COOLDOWN_SEC     => 1.0,    # Min seconds between requests
    REQUEST_TIMEOUT  => 5,      # Seconds before giving up
    RATE_LIMIT_PER_MIN => 12,   # Max requests per minute
};

sub new {
    my ($class, %opts) = @_;
    return bless {
        # Config (loaded from Preferences + StateStore)
        provider_id => $opts{provider_id} || '',
        api_url    => $opts{api_url}  || '',
        api_key    => $opts{api_key}  || '',
        model      => $opts{model}    || '',
        enabled    => 0,

        # Async state
        _handle    => undef,   # Zepto::AIHttp request handle
        _buffer    => '',
        _request_id => 0,

        # Result
        _result    => undef,    # Latest completion text
        _pending   => 0,        # Request in flight
        _context_hash => '',    # Hash of last request context (dedup)

        # Timing
        _last_request_time => 0,
        _request_times     => [],   # Ring buffer for rate limiting
        _trigger_at        => 0,    # When to fire next request (debounce)

        # Dismiss tracking
        _dismissed_at      => 0,    # Last time user dismissed AI suggestion
    }, $class;
}

# Load config from Preferences and StateStore
sub load_config {
    my ($self, $prefs, $state_store) = @_;
    return unless $state_store;

    if ($prefs) {
        $self->{provider_id} = $prefs->get('ai_provider') // '';
        $self->{api_url}     = $prefs->get('ai_api_url')  // '';
        $self->{model}       = $prefs->get('ai_model')    // '';
    }

    # API key comes from secrets (not in Preferences for security)
    my $secrets = $state_store->get('secrets');
    $self->{api_key} = $secrets->{ai_api_key} || '';

    # "Enabled" here means "the user has turned the toggle on". Whether the
    # feature can actually fire a request also depends on ready() — see
    # cmd_toggle_ai's consent flow in Editor::Commands, which is the only
    # code path that should set this to 1.
    $self->{enabled} = 0;
}

sub is_enabled  { $_[0]->{enabled} }
sub is_pending  { $_[0]->{_pending} }
sub has_result  { defined $_[0]->{_result} }
sub result      { $_[0]->{_result} }
sub clear_result { $_[0]->{_result} = undef }
sub provider_id { $_[0]->{provider_id} }
sub api_url     { $_[0]->{api_url} }
sub model       { $_[0]->{model} }

# Is the feature fully configured and able to fire a request right now?
# (curl present, endpoint configured, and a key present unless the
# provider explicitly requires none — e.g. ollama).
sub ready {
    my ($self) = @_;
    return 0 unless Zepto::AIHttp::curl_available();
    return 0 unless length($self->{api_url});
    return 0 unless length($self->{model});
    my $provider = Zepto::AIProviders::get($self->{provider_id});
    my $needs_key = !$provider || (($provider->{auth} // 'bearer') ne 'none');
    return 0 if $needs_key && !length($self->{api_key});
    return 1;
}

# Why the feature isn't ready right now — used for the 'ai!' status pill
# and error messages. Returns '' if ready() is true.
sub not_ready_reason {
    my ($self) = @_;
    return '' if $self->ready();
    return 'curl not found on PATH' unless Zepto::AIHttp::curl_available();
    return 'not configured' unless length($self->{api_url}) && length($self->{model});
    return 'no API key';
}

# =============================================================================
# Trigger / Cancel / Poll
# =============================================================================

# Schedule a completion request (debounced)
sub trigger {
    my ($self, $doc, $view, $highlighter) = @_;
    return unless $self->{enabled} && $self->ready();

    # Don't trigger during cooldown after dismiss
    return if (time() - $self->{_dismissed_at}) < COOLDOWN_SEC;

    $self->{_trigger_at} = time() + DEBOUNCE_SEC;
    $self->{_trigger_doc}  = $doc;
    $self->{_trigger_view} = $view;
    $self->{_trigger_hl}   = $highlighter;
}

# Called from event loop on timeout — checks if debounce elapsed
sub check_trigger {
    my ($self) = @_;
    return 0 unless $self->{_trigger_at} > 0;
    return 0 unless time() >= $self->{_trigger_at};

    $self->{_trigger_at} = 0;
    my $doc  = delete $self->{_trigger_doc};
    my $view = delete $self->{_trigger_view};
    my $hl   = delete $self->{_trigger_hl};
    return 0 unless $doc && $view;

    $self->_fire_request($doc, $view, $hl);
    return 1;
}

# Cancel any pending or in-flight request
sub cancel {
    my ($self) = @_;
    $self->{_trigger_at} = 0;
    $self->{_result} = undef;
    $self->_kill_child();
}

# Mark as dismissed by user (starts cooldown)
sub dismiss {
    my ($self) = @_;
    $self->{_dismissed_at} = time();
    $self->cancel();
}

# Poll for results from the child process (non-blocking)
# Returns 1 if new result available, 0 otherwise
sub poll {
    my ($self) = @_;
    return 0 unless $self->{_handle};

    if ($self->{_pending} && Zepto::AIHttp::timed_out($self->{_handle}, REQUEST_TIMEOUT)) {
        $self->_kill_child();
        return 0;
    }

    my $state = Zepto::AIHttp::poll($self->{_handle}, \$self->{_buffer});
    if ($state eq 'done') {
        $self->_finish_request();
        return defined $self->{_result} ? 1 : 0;
    }

    return 0;
}

# Is the debounce timer active?
sub is_debouncing {
    my ($self) = @_;
    return $self->{_trigger_at} > 0;
}

# =============================================================================
# Request Building and Execution
# =============================================================================

sub _fire_request {
    my ($self, $doc, $view, $hl) = @_;

    # Rate limiting
    my $now = time();
    my @recent = grep { $_ > $now - 60 } @{$self->{_request_times}};
    if (@recent >= RATE_LIMIT_PER_MIN) {
        return;
    }

    # Build context
    my ($prefix, $suffix, $language, $filename) = $self->_build_context($doc, $view, $hl);

    # Dedup: don't resend identical context
    my $ctx_hash = _hash("$prefix|||$suffix");
    if ($ctx_hash eq $self->{_context_hash} && defined $self->{_result}) {
        return;  # Same context, same result
    }

    # Cancel any existing request
    $self->_kill_child();

    my $provider = Zepto::AIProviders::get($self->{provider_id}) || { auth => 'bearer' };

    my $system_msg = 'Complete the code/text at the cursor. Reply with ONLY the continuation, no explanation, no quotes.';
    my $lang_hint  = $language ? " ($language)" : '';
    my $file_hint  = $filename ? "File: $filename$lang_hint\n\n" : '';
    my $user_msg   = "${file_hint}${prefix}<CURSOR>${suffix}";

    my $req_data = Zepto::AIProviders::build_completion_request(
        model      => $self->{model},
        system     => $system_msg,
        user       => $user_msg,
        max_tokens => MAX_OUTPUT_TOKENS,
    );
    my $body = eval { JSON::PP->new->utf8->encode($req_data) };
    return unless defined $body;

    my @headers = (['Content-Type', 'application/json']);
    push @headers, @{ Zepto::AIProviders::auth_headers($provider, $self->{api_key}) };

    my $handle = Zepto::AIHttp::start_request(
        method  => 'POST',
        url     => $self->{api_url} . '/chat/completions',
        headers => \@headers,
        body    => $body,
        timeout => REQUEST_TIMEOUT,
    );
    return unless $handle;

    $self->{_context_hash} = $ctx_hash;
    $self->{_pending} = 1;
    $self->{_buffer} = '';
    $self->{_result} = undef;
    $self->{_last_request_time} = $now;
    push @{$self->{_request_times}}, $now;
    $self->{_request_id}++;
    $self->{_handle} = $handle;
}

sub _build_context {
    my ($self, $doc, $view, $hl) = @_;

    my $cursor_line = $view->cursor_line();
    my $cursor_col  = $view->cursor_col();
    my $line_count  = $doc->line_count();

    # Prefix: lines before and including cursor line up to cursor col
    my $prefix_start = ($cursor_line - PREFIX_LINES > 0) ? $cursor_line - PREFIX_LINES : 0;
    my @prefix_lines;
    for my $i ($prefix_start .. $cursor_line - 1) {
        push @prefix_lines, $doc->get_line_content($i) . "\n";
    }
    # Current line up to cursor
    my $current_line = $doc->get_line_content($cursor_line) // '';
    push @prefix_lines, substr($current_line, 0, $cursor_col);
    my $prefix = join('', @prefix_lines);

    # Suffix: rest of cursor line + lines after
    my $suffix_end = ($cursor_line + SUFFIX_LINES < $line_count) ? $cursor_line + SUFFIX_LINES : $line_count - 1;
    my @suffix_lines;
    push @suffix_lines, substr($current_line, $cursor_col);
    for my $i ($cursor_line + 1 .. $suffix_end) {
        push @suffix_lines, "\n" . $doc->get_line_content($i);
    }
    my $suffix = join('', @suffix_lines);

    # Language detection
    my $language = '';
    if ($hl) {
        my $grammar = $hl->{grammar};
        if ($grammar) {
            $language = ref($grammar);
            $language =~ s/^Zepto::Syntax:://;
        }
    }

    my $filename = $doc->filename() // $doc->path() // '';

    return ($prefix, $suffix, $language, $filename);
}

# =============================================================================
# Response Parsing
# =============================================================================

sub _finish_request {
    my ($self) = @_;

    my ($body, $status) = Zepto::AIHttp::extract_status($self->{_buffer});

    if ($status && !Zepto::AIHttp::is_network_error($status) && $status =~ /^2/) {
        my $data = eval { JSON::PP->new->utf8->decode($body) };
        if (!$@ && $data) {
            my $text = Zepto::AIProviders::parse_completion_response($data);
            if (defined $text) {
                # First line only, trimmed — ghost text is a single-line
                # suggestion.
                $text =~ s/\r\n/\n/g;
                ($text) = split /\n/, $text, 2;
                $text =~ s/^\s+//;
                $text =~ s/\s+$//;
                $self->{_result} = length($text) ? $text : undef;
            }
        }
    }

    # Clean up
    Zepto::AIHttp::finish($self->{_handle});
    $self->{_handle} = undef;
    $self->{_pending} = 0;
}

sub _kill_child {
    my ($self) = @_;
    if ($self->{_handle}) {
        Zepto::AIHttp::kill_request($self->{_handle});
        $self->{_handle} = undef;
    }
    $self->{_pending} = 0;
    $self->{_buffer} = '';
}

# =============================================================================
# Utilities
# =============================================================================

sub _hash {
    my ($s) = @_;
    # Simple hash for dedup — not cryptographic
    my $h = 0;
    for my $c (unpack('C*', substr($s, 0, 500))) {
        $h = (($h << 5) - $h + $c) & 0xFFFFFFFF;
    }
    return $h;
}

# Cleanup on destroy
sub DESTROY {
    my ($self) = @_;
    $self->_kill_child();
}

1;
