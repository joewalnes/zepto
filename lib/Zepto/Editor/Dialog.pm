package Zepto::Editor::Dialog;
# =============================================================================
# Editor Dialog Handling - Generic multi-field modal dialog (STATE_DIALOG)
# =============================================================================
#
# A minimal multi-field modal dialog widget. Currently used by the AI
# Settings dialog (open_ai_dialog), but the field/list-picker machinery is
# generic: fields are one of 'text', 'masked', 'select', or 'button'.
#
#   text/masked — backed by a Zepto::InputWidget; 'masked' renders dots
#                 with the last 4 characters visible instead of plaintext.
#   select      — Enter opens a filterable full-screen-in-dialog list
#                 picker (reuses InputWidget for the filter text and the
#                 command registry's fuzzy scorer for ranking).
#   button      — Enter activates an action callback.
#
# Navigation: Tab/Shift-Tab/Up/Down move focus between fields. Enter
# activates the focused field. Esc cancels (in list mode, Esc backs out to
# the form instead of closing the whole dialog).
# =============================================================================

use strict;
use warnings;
use utf8;

# Define methods in Zepto::Editor's namespace
package Zepto::Editor;

use Zepto::InputWidget;
use Zepto::AIProviders;
use Zepto::AIHttp;
use Zepto::CommandRegistry;
use JSON::PP ();

# =============================================================================
# AI Settings dialog (the concrete use of this generic widget today)
# =============================================================================

sub open_ai_dialog {
    my ($self) = @_;
    my $prefs = $self->{prefs};
    my $store = $self->{state_store};

    my $provider_id = ($prefs && $prefs->get('ai_provider')) || 'openai';
    my $provider = Zepto::AIProviders::get($provider_id) || Zepto::AIProviders::get('openai');
    $provider_id = $provider->{id};

    my $base_url = ($prefs && $prefs->get('ai_api_url')) || '';
    $base_url = $provider->{base_url} unless length($base_url);

    my $secrets = $store ? $store->get('secrets') : {};
    my $api_key = $secrets->{ai_api_key} // '';

    my $model = ($prefs && $prefs->get('ai_model')) || $provider->{default_model} || '';

    $self->{state} = 'dialog';
    $self->{dialog} = {
        title         => 'AI: Configure',
        focus         => 0,
        status_text   => '',
        status_kind   => '',   # '' | 'pending' | 'ok' | 'error'
        list_mode     => 0,
        model_options => [],
        fields => [
            { id => 'provider', label => 'Provider',  type => 'select', value => $provider_id },
            { id => 'base_url', label => 'Base URL',  type => 'text',   widget => Zepto::InputWidget->new(value => $base_url) },
            { id => 'api_key',  label => 'API Key',   type => 'masked', widget => Zepto::InputWidget->new(value => $api_key) },
            { id => 'test',     label => 'Test Connection', type => 'button' },
            { id => 'model',    label => 'Model',      type => 'select', value => $model },
            { id => 'save',     label => 'Save',        type => 'button' },
            { id => 'cancel',   label => 'Cancel',      type => 'button' },
        ],
    };

    unless (Zepto::AIHttp::curl_available()) {
        $self->{dialog}{status_text} = 'AI completion requires curl (not found on PATH)';
        $self->{dialog}{status_kind} = 'error';
    }
}

# =============================================================================
# Generic dialog lifecycle
# =============================================================================

sub close_dialog {
    my ($self) = @_;
    if ($self->{dialog} && $self->{dialog}{_test_handle}) {
        Zepto::AIHttp::kill_request($self->{dialog}{_test_handle});
    }
    $self->{state} = 'editing';
    $self->{dialog} = undef;
}

# Poll any in-flight Test Connection request. Returns 1 if state changed
# (caller should re-render). Called from the main event loop's idle tick.
sub dialog_test_active {
    my ($self) = @_;
    return $self->{dialog} && $self->{dialog}{_test_handle} ? 1 : 0;
}

sub dialog_poll_test {
    my ($self) = @_;
    my $d = $self->{dialog};
    return 0 unless $d && $d->{_test_handle};

    if (Zepto::AIHttp::timed_out($d->{_test_handle}, 10)) {
        Zepto::AIHttp::kill_request($d->{_test_handle});
        $d->{_test_handle} = undef;
        $d->{status_text} = 'Timed out';
        $d->{status_kind} = 'error';
        return 1;
    }

    my $state = Zepto::AIHttp::poll($d->{_test_handle}, \$d->{_test_buf});
    return 0 if $state eq 'pending';

    Zepto::AIHttp::finish($d->{_test_handle});
    $d->{_test_handle} = undef;

    my ($body, $status) = Zepto::AIHttp::extract_status($d->{_test_buf});

    if (Zepto::AIHttp::is_network_error($status)) {
        $d->{status_text} = "Network error - could not reach $d->{_test_base_url}";
        $d->{status_kind} = 'error';
        return 1;
    }

    if ($status !~ /^2/) {
        # Auth failure: retry with the next auth variant if the provider
        # has one (Anthropic's /models needs native headers as a fallback
        # when the OpenAI-compatible Bearer form is rejected).
        if (($status eq '401' || $status eq '403')
            && $d->{_test_variant_idx} + 1 < scalar(@{$d->{_test_variants}})) {
            $d->{_test_variant_idx}++;
            $self->_dialog_start_models_request();
            return 1;
        }
        my $data = eval { JSON::PP->new->utf8->decode($body) };
        my $msg = (!$@ && $data) ? Zepto::AIProviders::parse_error_message($data) : undef;
        $d->{status_text} = "Error $status" . ($msg ? ": $msg" : '');
        $d->{status_kind} = 'error';
        return 1;
    }

    my $data = eval { JSON::PP->new->utf8->decode($body) };
    if ($@ || !$data) {
        $d->{status_text} = 'OK, but response was not valid JSON';
        $d->{status_kind} = 'error';
        return 1;
    }
    my @models = Zepto::AIProviders::parse_models_response($data);
    $d->{model_options} = \@models;
    $d->{status_text} = 'OK - ' . scalar(@models) . ' models';
    $d->{status_kind} = 'ok';

    my $model_field = $self->_dialog_field('model');
    if (@models && $model_field) {
        my $default = ($d->{_test_provider} || {})->{default_model} || '';
        if ($default && grep { $_ eq $default } @models) {
            $model_field->{value} = $default;
        }
        elsif (!length($model_field->{value}) || !grep { $_ eq $model_field->{value} } @models) {
            $model_field->{value} = $models[0];
        }
    }
    return 1;
}

# =============================================================================
# Event handling
# =============================================================================

sub handle_dialog_event {
    my ($self, $event) = @_;
    my $d = $self->{dialog};
    return unless $d;
    return $self->_dialog_handle_list_event($event) if $d->{list_mode};

    my $type = $event->{type};
    if ($type eq 'key') {
        my $key = $event->{key};
        my $shift = Zepto::InputParser::has_modifier($event, 'shift');
        if ($key eq 'escape') { $self->close_dialog(); return; }
        if ($key eq 'tab')    { $shift ? $self->_dialog_focus_prev() : $self->_dialog_focus_next(); return; }
        if ($key eq 'down')   { $self->_dialog_focus_next(); return; }
        if ($key eq 'up')     { $self->_dialog_focus_prev(); return; }
        if ($key eq 'enter')  { $self->_dialog_activate_focused(); return; }
    }

    # Everything else (typed characters, left/right/home/end/backspace/
    # delete) goes to the focused field's text widget, if it has one.
    my $field = $d->{fields}[$d->{focus}];
    return unless $field && ($field->{type} eq 'text' || $field->{type} eq 'masked');
    $field->{widget}->handle_event($event, \$self->{clipboard});
}

sub _dialog_focus_next {
    my ($self) = @_;
    my $d = $self->{dialog} or return;
    my $n = scalar @{$d->{fields}};
    $d->{focus} = ($d->{focus} + 1) % $n;
}

sub _dialog_focus_prev {
    my ($self) = @_;
    my $d = $self->{dialog} or return;
    my $n = scalar @{$d->{fields}};
    $d->{focus} = ($d->{focus} - 1 + $n) % $n;
}

sub _dialog_field {
    my ($self, $id) = @_;
    my $d = $self->{dialog} or return undef;
    for my $f (@{$d->{fields}}) {
        return $f if $f->{id} eq $id;
    }
    return undef;
}

sub _dialog_activate_focused {
    my ($self) = @_;
    my $d = $self->{dialog};
    my $field = $d->{fields}[$d->{focus}];
    return unless $field;

    if ($field->{type} eq 'select') {
        $self->_dialog_open_list($field->{id});
    }
    elsif ($field->{id} eq 'test') {
        $self->_dialog_run_test();
    }
    elsif ($field->{id} eq 'save') {
        $self->_dialog_save();
    }
    elsif ($field->{id} eq 'cancel') {
        $self->close_dialog();
    }
    elsif ($field->{type} eq 'text' || $field->{type} eq 'masked') {
        $self->_dialog_focus_next();
    }
}

# =============================================================================
# List picker (provider / model)
# =============================================================================

sub _dialog_open_list {
    my ($self, $field_id) = @_;
    my $d = $self->{dialog};
    my @options;

    if ($field_id eq 'provider') {
        @options = map { { id => $_->{id}, label => $_->{name} } } Zepto::AIProviders::list();
    }
    elsif ($field_id eq 'model') {
        my $models = $d->{model_options} || [];
        unless (@$models) {
            $d->{status_text} = 'Run Test Connection to list available models';
            $d->{status_kind} = 'error';
            return;
        }
        @options = map { { id => $_, label => $_ } } @$models;
    }
    else {
        return;
    }

    $d->{list_mode}    = 1;
    $d->{list_field}   = $field_id;
    $d->{list_widget}  = Zepto::InputWidget->new();
    $d->{list_options} = \@options;
    $d->{list_cursor}  = 0;
    $self->_dialog_list_refilter();

    my $current = $self->_dialog_field($field_id)->{value};
    for my $i (0 .. $#{$d->{list_filtered}}) {
        if ($d->{list_filtered}[$i]{id} eq $current) { $d->{list_cursor} = $i; last; }
    }
}

sub _dialog_list_refilter {
    my ($self) = @_;
    my $d = $self->{dialog};
    my $query = lc($d->{list_widget}->value());
    my @opts = @{$d->{list_options}};

    if (length($query)) {
        my @scored;
        for my $o (@opts) {
            my $score = Zepto::CommandRegistry::_fuzzy_score($query, lc($o->{label}));
            push @scored, [$score, $o] if $score > 0;
        }
        @scored = sort { $b->[0] <=> $a->[0] } @scored;
        @opts = map { $_->[1] } @scored;
    }

    $d->{list_filtered} = \@opts;
    $d->{list_cursor} = 0 if $d->{list_cursor} >= @opts;
}

sub _dialog_handle_list_event {
    my ($self, $event) = @_;
    my $d = $self->{dialog};
    my $type = $event->{type};

    if ($type eq 'key') {
        my $key = $event->{key};
        if ($key eq 'escape') { $d->{list_mode} = 0; return; }
        if ($key eq 'up')     { $d->{list_cursor}-- if $d->{list_cursor} > 0; return; }
        if ($key eq 'down')   { $d->{list_cursor}++ if $d->{list_cursor} < $#{$d->{list_filtered}}; return; }
        if ($key eq 'enter')  { $self->_dialog_list_confirm(); return; }
    }

    if ($d->{list_widget}->handle_event($event, \$self->{clipboard})) {
        $self->_dialog_list_refilter();
    }
}

sub _dialog_list_confirm {
    my ($self) = @_;
    my $d = $self->{dialog};
    my $opt = $d->{list_filtered}[$d->{list_cursor}];
    return unless $opt;

    my $field = $self->_dialog_field($d->{list_field});
    $field->{value} = $opt->{id};

    if ($d->{list_field} eq 'provider') {
        my $provider = Zepto::AIProviders::get($opt->{id});
        if ($provider) {
            $self->_dialog_field('base_url')->{widget}->set_value($provider->{base_url});
            my $model_field = $self->_dialog_field('model');
            $model_field->{value} = $provider->{default_model} || '';
        }
        $d->{model_options} = [];
        $d->{status_text} = '';
        $d->{status_kind} = '';
    }

    $d->{list_mode} = 0;
}

# =============================================================================
# Test Connection
# =============================================================================

sub _dialog_run_test {
    my ($self) = @_;
    my $d = $self->{dialog};
    return if $d->{_test_handle};

    unless (Zepto::AIHttp::curl_available()) {
        $d->{status_text} = 'AI completion requires curl (not found on PATH)';
        $d->{status_kind} = 'error';
        return;
    }

    my $provider_id = $self->_dialog_field('provider')->{value};
    my $provider = Zepto::AIProviders::get($provider_id) || { id => $provider_id, auth => 'bearer' };
    my $base_url = $self->_dialog_field('base_url')->{widget}->value();
    my $key      = $self->_dialog_field('api_key')->{widget}->value();

    unless (length($base_url)) {
        $d->{status_text} = 'Base URL is required';
        $d->{status_kind} = 'error';
        return;
    }

    $d->{_test_provider}    = $provider;
    $d->{_test_base_url}    = $base_url;
    $d->{_test_key}         = $key;
    $d->{_test_variants}    = [ Zepto::AIProviders::models_auth_variants($provider) ];
    $d->{_test_variant_idx} = 0;

    $self->_dialog_start_models_request();
}

sub _dialog_start_models_request {
    my ($self) = @_;
    my $d = $self->{dialog};
    my $variant = $d->{_test_variants}[$d->{_test_variant_idx}] // 'default';

    my @headers = @{ Zepto::AIProviders::auth_headers($d->{_test_provider}, $d->{_test_key}, $variant) };

    $d->{status_text} = 'Testing...';
    $d->{status_kind} = 'pending';
    $d->{_test_buf}   = '';
    $d->{_test_handle} = Zepto::AIHttp::start_request(
        method  => 'GET',
        url     => $d->{_test_base_url} . '/models',
        headers => \@headers,
        timeout => 10,
    );
    unless ($d->{_test_handle}) {
        $d->{status_text} = 'AI completion requires curl (not found on PATH)';
        $d->{status_kind} = 'error';
    }
}

# =============================================================================
# Save
# =============================================================================

sub _dialog_save {
    my ($self) = @_;
    my $d = $self->{dialog};

    my $provider_id = $self->_dialog_field('provider')->{value};
    my $base_url    = $self->_dialog_field('base_url')->{widget}->value();
    my $api_key     = $self->_dialog_field('api_key')->{widget}->value();
    my $model       = $self->_dialog_field('model')->{value};

    unless (length($base_url) && length($model)) {
        $d->{status_text} = 'Base URL and Model are required';
        $d->{status_kind} = 'error';
        return;
    }

    my $prefs = $self->{prefs};
    if ($prefs) {
        $prefs->set('ai_provider', $provider_id);
        $prefs->set('ai_api_url', $base_url);
        $prefs->set('ai_model', $model);
    }
    if ($self->{state_store}) {
        $self->{state_store}->put('secrets', { ai_api_key => $api_key });
    }
    if ($self->{_ai_complete}) {
        $self->{_ai_complete}->load_config($prefs, $self->{state_store});
    }

    $self->close_dialog();
    $self->show_message("AI: configured ($provider_id / $model). Use 'AI: Toggle Completion' to enable.");
}

1;
