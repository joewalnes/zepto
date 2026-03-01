package Zepto::Preferences;
# =============================================================================
# Preferences: Editor configuration with defaults
# =============================================================================
#
# Stores editor preferences in memory. Later can be extended to support
# persistent storage (file-based or XDG config).
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
    powerline        => 1,            # Use Powerline/Nerd Font glyphs
    show_minimap     => 1,            # Show minimap/scrollbar
    show_tree        => 1,            # Show file tree panel
    word_wrap        => 0,            # Word wrap mode (break long lines at viewport edge)

    # Editing
    tab_width        => 4,
    soft_tabs        => 1,        # Use spaces instead of tabs
    auto_indent      => 1,        # Copy indentation from previous line

    # Search
    search_case_sensitive => 0,
    search_regex     => 0,
    search_wrap      => 1,        # Wrap around at end of document

    # Behavior
    confirm_quit_unsaved => 1,    # Confirm before closing unsaved
    mouse_enabled    => 1,
    scroll_margin    => 3,        # Lines to keep above/below cursor

    # File handling
    backup_on_save   => 0,        # Create .bak files
    trim_trailing_whitespace => 0,
    ensure_final_newline => 1,
);

sub new {
    my ($class, %initial) = @_;

    my $self = bless {
        prefs => { %DEFAULTS },
        _callbacks => {},
    }, $class;

    # Apply any initial values
    for my $key (keys %initial) {
        $self->set($key, $initial{$key});
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

sub powerline { $_[0]->get('powerline') }
sub set_powerline { $_[0]->set('powerline', $_[1]) }

sub show_minimap { $_[0]->get('show_minimap') }
sub set_show_minimap { $_[0]->set('show_minimap', $_[1]) }

sub show_tree { $_[0]->get('show_tree') }
sub set_show_tree { $_[0]->set('show_tree', $_[1]) }

sub word_wrap { $_[0]->get('word_wrap') }
sub set_word_wrap { $_[0]->set('word_wrap', $_[1]) }

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
# Persistence (for future use)
# =============================================================================

# Serialize preferences to a string (simple key=value format)
sub serialize {
    my ($self) = @_;
    my $output = '';
    for my $key (sort CORE::keys %{$self->{prefs}}) {
        my $value = $self->{prefs}{$key};
        $value //= '';
        $output .= "$key=$value\n";
    }
    return $output;
}

# Load preferences from a string
sub deserialize {
    my ($self, $input) = @_;
    return unless defined $input;

    for my $line (split /\n/, $input) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if $line =~ /^#/ || $line eq '';

        if ($line =~ /^([^=]+)=(.*)$/) {
            my ($key, $value) = ($1, $2);
            $key =~ s/\s+$//;
            $value =~ s/^\s+//;

            # Convert 'true'/'false' to 1/0 for booleans
            $value = 1 if $value eq 'true';
            $value = 0 if $value eq 'false';

            $self->set($key, $value) if exists $DEFAULTS{$key};
        }
    }

    return 1;
}

1;
