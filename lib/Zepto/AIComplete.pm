package Zepto::AIComplete;
# =============================================================================
# AIComplete: Async AI code completion via OpenAI-compatible API
# =============================================================================
#
# Uses fork+pipe to make non-blocking HTTP requests to an OpenAI-compatible
# API endpoint. The editor event loop polls the pipe for results.
#
# Features:
#   - Async: never blocks the editor event loop
#   - Debounced: waits for typing pause before requesting
#   - Cancellable: new keystrokes abort in-flight requests
#   - Streaming: shows partial results as they arrive
#   - Rate-limited: max ~10 requests/minute
#   - Cost-aware: limits context and output tokens
# =============================================================================

use strict;
use warnings;
use IO::Select;
use POSIX qw(:sys_wait_h);
use File::Spec;

# Context and output limits
use constant {
    PREFIX_LINES     => 100,    # Lines before cursor to send
    SUFFIX_LINES     => 50,     # Lines after cursor to send
    MAX_OUTPUT_TOKENS => 200,   # Max tokens in completion response
    DEBOUNCE_SEC     => 0.5,    # Seconds of inactivity before triggering
    COOLDOWN_SEC     => 1.0,    # Min seconds between requests
    REQUEST_TIMEOUT  => 5,      # Seconds before giving up
    RATE_LIMIT_PER_MIN => 12,   # Max requests per minute
};

sub new {
    my ($class, %opts) = @_;
    return bless {
        # Config (loaded from StateStore)
        api_url    => $opts{api_url}  || '',
        api_key    => $opts{api_key}  || '',
        model      => $opts{model}    || '',
        enabled    => 0,

        # Async state
        _pid       => undef,
        _pipe      => undef,
        _select    => undef,
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

    # URL and model come from Preferences (which has defaults)
    if ($prefs) {
        $self->{api_url} = $prefs->get('ai_api_url');
        $self->{model}   = $prefs->get('ai_model');
    }

    # API key comes from secrets (not in Preferences for security)
    my $secrets = $state_store->get('secrets');
    $self->{api_key} = $secrets->{ai_api_key} || '';

    $self->{enabled} = length($self->{api_key}) ? 1 : 0;
}

sub is_enabled  { $_[0]->{enabled} }
sub is_pending  { $_[0]->{_pending} }
sub has_result  { defined $_[0]->{_result} }
sub result      { $_[0]->{_result} }
sub clear_result { $_[0]->{_result} = undef }

# =============================================================================
# Trigger / Cancel / Poll
# =============================================================================

# Schedule a completion request (debounced)
sub trigger {
    my ($self, $doc, $view, $highlighter) = @_;
    return unless $self->{enabled};

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
    return 0 unless $self->{_pipe} && $self->{_select};

    # Check for timeout
    if ($self->{_pending} && (time() - $self->{_last_request_time}) > REQUEST_TIMEOUT) {
        $self->_kill_child();
        return 0;
    }

    my $got_data = 0;
    while ($self->{_select} && $self->{_select}->can_read(0)) {
        my $buf;
        my $n = sysread($self->{_pipe}, $buf, 4096);
        if (!defined $n || $n == 0) {
            # EOF or error — child done
            $self->_finish_request();
            return defined $self->{_result} ? 1 : 0;
        }
        $self->{_buffer} .= $buf;
        $got_data = 1;
    }

    # Parse streaming chunks as they arrive
    if ($got_data && length($self->{_buffer})) {
        $self->_parse_streaming_buffer();
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

    $self->{_context_hash} = $ctx_hash;
    $self->{_pending} = 1;
    $self->{_buffer} = '';
    $self->{_result} = undef;
    $self->{_last_request_time} = $now;
    push @{$self->{_request_times}}, $now;
    $self->{_request_id}++;

    # Build the request payload
    my $payload = $self->_build_payload($prefix, $suffix, $language, $filename);

    # Fork child to make HTTP request
    pipe(my $read_end, my $write_end) or return;

    my $pid = fork();
    if (!defined $pid) {
        close($read_end);
        close($write_end);
        $self->{_pending} = 0;
        return;
    }

    if ($pid == 0) {
        # Child process: make HTTP request and write result to pipe
        close($read_end);
        $self->_child_http_request($write_end, $payload);
        close($write_end);
        POSIX::_exit(0);
    }

    # Parent
    close($write_end);
    $self->{_pid} = $pid;
    $self->{_pipe} = $read_end;
    $self->{_select} = IO::Select->new($read_end);
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

sub _build_payload {
    my ($self, $prefix, $suffix, $language, $filename) = @_;

    # Use chat completion format (most compatible)
    my $lang_hint = $language ? " ($language)" : '';
    my $file_hint = $filename ? "File: $filename$lang_hint\n\n" : '';

    # Escape for JSON
    my $system_msg = _json_escape("You are a code completion assistant. You will be given code with a <CURSOR> marker. Output ONLY the code that should be inserted at the cursor position. Do not repeat any existing code. Do not add explanations, markdown formatting, or comments about the completion. Output nothing if no completion is appropriate. Keep completions short - usually 1-3 lines.");
    my $user_msg = _json_escape("${file_hint}${prefix}<CURSOR>${suffix}");
    my $model = _json_escape($self->{model});

    return qq({"model":"$model","messages":[{"role":"system","content":"$system_msg"},{"role":"user","content":"$user_msg"}],"max_tokens":) . MAX_OUTPUT_TOKENS . qq(,"temperature":0,"stream":true,"stop":["\\n\\n\\n"]});
}

# Child process: make HTTP request using curl (reliable, handles SSL/chunked)
sub _child_http_request {
    my ($self, $write_fh, $payload) = @_;

    my $api_url = $self->{api_url};
    my $api_key = $self->{api_key};
    my $url = $api_url . '/chat/completions';

    # Redirect stdout to our pipe, suppress stderr
    open(STDOUT, '>&', $write_fh) or return;
    open(STDERR, '>', '/dev/null');
    close($write_fh);

    # Use curl with streaming — outputs SSE data lines directly
    exec('curl', '-sS', '-N',
        '-X', 'POST',
        '-H', 'Content-Type: application/json',
        '-H', "Authorization: Bearer $api_key",
        '-d', $payload,
        '--max-time', REQUEST_TIMEOUT,
        $url,
    );
    # exec failed
}

# =============================================================================
# Response Parsing
# =============================================================================

sub _parse_streaming_buffer {
    my ($self) = @_;

    # Parse SSE data: lines starting with "data: "
    my $text = '';
    while ($self->{_buffer} =~ s/^data:\s*(.*?)\r?\n//m) {
        my $data = $1;
        next if $data eq '[DONE]';

        # Parse JSON minimally — extract content delta
        if ($data =~ /"delta"\s*:\s*\{[^}]*"content"\s*:\s*"((?:[^"\\]|\\.)*)"/s) {
            my $chunk = $1;
            # Unescape JSON string
            $chunk =~ s/\\n/\n/g;
            $chunk =~ s/\\t/\t/g;
            $chunk =~ s/\\"/"/g;
            $chunk =~ s/\\\\/\\/g;
            $text .= $chunk;
        }
    }

    if (length($text)) {
        $self->{_result} = ($self->{_result} // '') . $text;
    }
}

sub _finish_request {
    my ($self) = @_;

    # Parse any remaining buffer
    $self->_parse_streaming_buffer() if length($self->{_buffer});

    # Clean up
    if ($self->{_pipe}) {
        close($self->{_pipe});
        $self->{_pipe} = undef;
    }
    $self->{_select} = undef;
    $self->{_pending} = 0;

    # Reap child
    if ($self->{_pid}) {
        waitpid($self->{_pid}, WNOHANG);
        $self->{_pid} = undef;
    }

    # Clean up result — trim leading/trailing whitespace artifacts
    if (defined $self->{_result}) {
        # Remove trailing whitespace-only content
        $self->{_result} =~ s/\s+$//;
        # If result is empty, clear it
        $self->{_result} = undef unless length($self->{_result} // '');
    }
}

sub _kill_child {
    my ($self) = @_;
    if ($self->{_pid}) {
        kill('TERM', $self->{_pid});
        waitpid($self->{_pid}, WNOHANG);
        $self->{_pid} = undef;
    }
    if ($self->{_pipe}) {
        close($self->{_pipe});
        $self->{_pipe} = undef;
    }
    $self->{_select} = undef;
    $self->{_pending} = 0;
    $self->{_buffer} = '';
}

# =============================================================================
# Utilities
# =============================================================================

sub _json_escape {
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/"/\\"/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    # Escape control characters
    $s =~ s/([\x00-\x1f])/sprintf("\\u%04x", ord($1))/ge;
    return $s;
}

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
