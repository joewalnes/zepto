package Zepto::Preferences;
# =============================================================================
# Preferences: Editor configuration with defaults and persistence
# =============================================================================
#
# Global preferences are persisted via StateStore and synced across instances.
# Per-window preferences (show_tree, word_wrap) are in-memory only, initialized
# from global defaults.
#
# Categories:
#   - Display: theme, line numbers, etc.
#   - Editing: tab width, soft tabs, auto-indent
#   - Search: case sensitivity, regex mode
# =============================================================================

use strict;
use warnings;

# Default preference values
my %DEFAULTS = (
    # Display
    theme            => 'dark',
    show_line_numbers => 1,
    show_status_bar  => 1,
    nerd_font        => 1,            # Use Nerd Font glyphs
    show_minimap     => 1,            # Show minimap/scrollbar
    show_tree        => 1,            # Show file tree panel (default for new windows)
    word_wrap        => 0,            # Word wrap mode (default for new windows)

    # Editing
    tab_width        => 4,
    soft_tabs        => 1,        # Use spaces instead of tabs
    auto_indent      => 1,        # Copy indentation from previous line

    # Search
    search_case_sensitive => 0,
    search_regex     => 0,
    search_wrap      => 1,        # Wrap around at end of document

    # Completion
    auto_complete        => 1,        # Auto-completion (ghost text + menu)
    auto_pairs           => 1,        # Auto-insert closing brackets/quotes

    # Behavior
    confirm_quit_unsaved => 1,    # Confirm before closing unsaved
    mouse_enabled    => 1,
    scroll_margin    => 3,        # Lines to keep above/below cursor

    # AI completion
    ai_api_url       => 'https://openrouter.ai/api/v1',
    ai_model         => 'anthropic/claude-haiku-4-5-20251001',

    # File handling
    backup_on_save   => 0,        # Create .bak files
    trim_trailing_whitespace => 0,
    ensure_final_newline => 1,
);

# Preferences that are persisted globally and synced across instances.
# Everything else is per-window or internal.
my %GLOBAL_PREFS = map { $_ => 1 } qw(
    theme
    show_line_numbers
    nerd_font
    show_minimap
    show_tree
    word_wrap
    tab_width
    soft_tabs
    auto_indent
    auto_complete
    auto_pairs
    mouse_enabled
    ai_api_url
    ai_model
);

sub new {
    my ($class, %opts) = @_;

    my $state_store = delete $opts{state_store};

    my $self = bless {
        prefs       => { %DEFAULTS },
        _callbacks  => {},
        _state_store => $state_store,
        _loading     => 0,  # Guard against persist-during-load
    }, $class;

    # Load persisted preferences from StateStore
    if ($state_store) {
        $self->_load_from_store();

        # Listen for cross-instance changes
        $state_store->on_change('preferences', sub {
            my ($data) = @_;
            $self->_apply_external_changes($data);
        });
    }

    # Apply any programmatic initial values (e.g. from tests)
    for my $key (CORE::keys %opts) {
        $self->set($key, $opts{$key});
    }

    return $self;
}

# Get a preference value
sub get {
    my ($self, $key) = @_;
    return undef unless defined $key;
    return $self->{prefs}{$key};
}

# Set a preference value
sub set {
    my ($self, $key, $value) = @_;
    return unless defined $key;

    my $old_value = $self->{prefs}{$key};
    $self->{prefs}{$key} = $value;

    # Notify callbacks if value changed
    if (!defined $old_value || !defined $value || $old_value ne $value) {
        $self->_notify($key, $value, $old_value);

        # Persist global prefs to StateStore (unless we're loading)
        if (!$self->{_loading} && $self->{_state_store} && $GLOBAL_PREFS{$key}) {
            $self->{_state_store}->put('preferences', { $key => $value });
        }
    }

    return $value;
}

# Get all preferences as a hash
sub all {
    my ($self) = @_;
    return %{$self->{prefs}};
}

# Reset a preference to default
sub reset {
    my ($self, $key) = @_;
    return unless defined $key && exists $DEFAULTS{$key};
    return $self->set($key, $DEFAULTS{$key});
}

# Reset all preferences to defaults
sub reset_all {
    my ($self) = @_;
    $self->{prefs} = { %DEFAULTS };
    return 1;
}

# Get default value for a preference
sub default {
    my ($self, $key) = @_;
    return $DEFAULTS{$key};
}

# Check if a preference exists
sub exists {
    my ($self, $key) = @_;
    return exists $self->{prefs}{$key};
}

# List all preference keys
sub keys {
    my ($self) = @_;
    return CORE::keys %{$self->{prefs}};
}

# =============================================================================
# Change notification
# =============================================================================

# Register a callback for preference changes
# Callback receives: ($key, $new_value, $old_value)
sub on_change {
    my ($self, $callback) = @_;
    return unless ref($callback) eq 'CODE';

    my $id = ++$self->{_callback_id};
    $self->{_callbacks}{$id} = $callback;
    return $id;
}

# Remove a change callback
sub off_change {
    my ($self, $id) = @_;
    delete $self->{_callbacks}{$id};
}

# Internal: notify callbacks of change
sub _notify {
    my ($self, $key, $new_value, $old_value) = @_;
    for my $cb (values %{$self->{_callbacks}}) {
        eval { $cb->($key, $new_value, $old_value) };
        # Ignore callback errors
    }
}

# =============================================================================
# Convenience accessors for common preferences
# =============================================================================

sub theme { $_[0]->get('theme') }
sub set_theme { $_[0]->set('theme', $_[1]) }

sub tab_width { $_[0]->get('tab_width') }
sub set_tab_width { $_[0]->set('tab_width', $_[1]) }

sub soft_tabs { $_[0]->get('soft_tabs') }
sub set_soft_tabs { $_[0]->set('soft_tabs', $_[1]) }

sub auto_indent { $_[0]->get('auto_indent') }
sub set_auto_indent { $_[0]->set('auto_indent', $_[1]) }

sub show_line_numbers { $_[0]->get('show_line_numbers') }
sub set_show_line_numbers { $_[0]->set('show_line_numbers', $_[1]) }

sub mouse_enabled { $_[0]->get('mouse_enabled') }
sub set_mouse_enabled { $_[0]->set('mouse_enabled', $_[1]) }

sub search_case_sensitive { $_[0]->get('search_case_sensitive') }
sub set_search_case_sensitive { $_[0]->set('search_case_sensitive', $_[1]) }

sub search_wrap { $_[0]->get('search_wrap') }
sub set_search_wrap { $_[0]->set('search_wrap', $_[1]) }

sub nerd_font { $_[0]->get('nerd_font') }
sub set_nerd_font { $_[0]->set('nerd_font', $_[1]) }

sub show_minimap { $_[0]->get('show_minimap') }
sub set_show_minimap { $_[0]->set('show_minimap', $_[1]) }

sub show_tree { $_[0]->get('show_tree') }
sub set_show_tree { $_[0]->set('show_tree', $_[1]) }

sub word_wrap { $_[0]->get('word_wrap') }
sub set_word_wrap { $_[0]->set('word_wrap', $_[1]) }

sub auto_complete { $_[0]->get('auto_complete') }
sub set_auto_complete { $_[0]->set('auto_complete', $_[1]) }

sub auto_pairs { $_[0]->get('auto_pairs') }
sub set_auto_pairs { $_[0]->set('auto_pairs', $_[1]) }

# Extensions that default to word wrap on (prose file types)
my %WRAP_DEFAULT_EXTENSIONS = map { $_ => 1 } qw(md txt rst adoc markdown text);

sub should_default_wrap {
    my ($self, $filename) = @_;
    return 0 unless defined $filename;
    if ($filename =~ /\.([^.]+)$/) {
        return 1 if exists $WRAP_DEFAULT_EXTENSIONS{lc $1};
    }
    return 0;
}

# =============================================================================
# Tab/space conversion helpers
# =============================================================================

# Convert tabs to spaces in a string according to preferences
sub expand_tabs {
    my ($self, $text) = @_;
    return $text unless defined $text;

    my $width = $self->tab_width();
    $text =~ s/\t/' ' x $width/ge;
    return $text;
}

# Get the string to insert for a "tab" keypress
# Returns spaces if soft_tabs is enabled, otherwise \t
sub tab_string {
    my ($self) = @_;
    return $self->soft_tabs() ? (' ' x $self->tab_width()) : "\t";
}

# Calculate the visual width of a string (accounting for tabs)
sub visual_width {
    my ($self, $text, $tab_width) = @_;
    $tab_width //= $self->tab_width();
    return 0 unless defined $text;

    my $width = 0;
    for my $char (split //, $text) {
        if ($char eq "\t") {
            # Tab goes to next multiple of tab_width
            $width += $tab_width - ($width % $tab_width);
        }
        else {
            $width++;
        }
    }
    return $width;
}

# =============================================================================
# Persistence via StateStore
# =============================================================================

sub _load_from_store {
    my ($self) = @_;
    my $data = $self->{_state_store}->get('preferences');
    return unless $data && %$data;

    $self->{_loading} = 1;
    for my $key (CORE::keys %$data) {
        # Only load known preferences
        if (exists $DEFAULTS{$key}) {
            $self->{prefs}{$key} = $data->{$key};
        }
    }
    $self->{_loading} = 0;
}

sub _apply_external_changes {
    my ($self, $data) = @_;
    return unless $data && %$data;

    $self->{_loading} = 1;
    for my $key (CORE::keys %$data) {
        next unless exists $DEFAULTS{$key} && $GLOBAL_PREFS{$key};
        my $old = $self->{prefs}{$key};
        my $new = $data->{$key};
        if (!defined $old || !defined $new || $old ne $new) {
            $self->{prefs}{$key} = $new;
            $self->_notify($key, $new, $old);
        }
    }
    $self->{_loading} = 0;
}

1;
