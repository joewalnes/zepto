package Zepto::Completion::Controller;
# =============================================================================
# Completion Controller: Orchestrates completion state and providers
# =============================================================================
#
# Manages ghost text and dropdown menu completion. Stays in STATE_EDITING —
# completion is an overlay during normal editing, not a modal state.
#
# Provider interface (duck-typed):
#   complete($context) -> [{text, score, kind}, ...]
#   $context = {prefix, line, col, content, doc, language}
# =============================================================================

use strict;
use warnings;

use constant {
    STATE_IDLE  => 0,   # Nothing showing
    STATE_GHOST => 1,   # Ghost text inline
    STATE_MENU  => 2,   # Dropdown menu open
};

sub new {
    my ($class) = @_;
    return bless {
        state       => STATE_IDLE,
        providers   => [],
        results     => [],       # Current completion candidates [{text, score, kind, body?}, ...]
        prefix      => '',       # Current word prefix being completed
        ghost_index => 0,        # Which result is shown as ghost text
        menu_index  => 0,        # Selected item in dropdown menu
        menu_scroll => 0,        # Scroll offset in menu
        _max_menu_visible => 8,  # Max visible items in dropdown
        _recent_provider => undef,  # RecentProvider ref for recording acceptances
    }, $class;
}

# Add a completion provider
sub add_provider {
    my ($self, $provider) = @_;
    push @{$self->{providers}}, $provider;
}

# Set the RecentProvider reference for recording accepted completions
sub set_recent_provider {
    my ($self, $provider) = @_;
    $self->{_recent_provider} = $provider;
}

# =============================================================================
# Trigger / Dismiss
# =============================================================================

# Called after char insert; extracts prefix, queries providers
sub trigger {
    my ($self, $doc, $view, $highlighter) = @_;

    my $line_num = $view->cursor_line();
    my $col = $view->cursor_col();

    return $self->dismiss() if $line_num >= $doc->line_count();

    my $line_content = $doc->get_line_content($line_num);
    my $prefix = _extract_prefix($line_content, $col);

    # Minimum prefix length for auto-trigger
    if (length($prefix) < 2) {
        return $self->dismiss();
    }

    # Text already sitting immediately after the cursor on this line. Used
    # below to reject self-referential candidates -- see the filter after
    # dedup for why this matters.
    my $after_cursor = substr($line_content, $col);

    # Build context for providers
    my $language = '';
    if ($highlighter) {
        my $grammar = $highlighter->{grammar};
        if ($grammar) {
            $language = ref($grammar);
            $language =~ s/^Zepto::Syntax:://;
        }
    }

    my $context = {
        prefix   => $prefix,
        line     => $line_content,
        line_num => $line_num,
        col      => $col,
        doc      => $doc,
        language => $language,
        highlighter => $highlighter,
    };

    # Query all providers and merge results
    my @all_results;
    for my $provider (@{$self->{providers}}) {
        my $results = eval { $provider->complete($context) };
        next unless $results && @$results;
        push @all_results, @$results;
    }

    # Deduplicate by text (keep highest score, but preserve snippet body)
    my %seen;     # text => index in @unique
    my @unique;
    for my $r (sort { $b->{score} <=> $a->{score} } @all_results) {
        if (exists $seen{$r->{text}}) {
            # If this duplicate has a snippet body and the kept one doesn't, merge it
            if ($r->{kind} eq 'snippet' && defined $r->{body}) {
                my $kept = $unique[$seen{$r->{text}}];
                if (!defined $kept->{body}) {
                    $kept->{body} = $r->{body};
                    $kept->{kind} = 'snippet';
                }
            }
            next;
        }
        $seen{$r->{text}} = scalar @unique;
        push @unique, $r;
    }

    # Filter out exact matches (prefix == text)
    @unique = grep { $_->{text} ne $prefix } @unique;

    # Filter out self-referential candidates: a provider (most commonly
    # CrossBufferWordProvider, which re-scans the active document on every
    # keystroke) can trivially "discover" the word the user is mid-typing
    # as a match for its own prefix -- e.g. typing "ab" at the front of an
    # existing word "row2000text" makes the buffer momentarily contain
    # "abrow2000text", which the word scanner happily returns as a
    # candidate for prefix "ab". Its suggested suffix ("row2000text") is
    # then just the text that's ALREADY sitting right after the cursor.
    # Ghost-text rendering has no way to know that and paints the suffix
    # straight after the real content, producing an on-screen duplicate of
    # the line's own tail (does not touch the buffer -- purely cosmetic,
    # but confusing and persistent). Reject any candidate whose suffix
    # would just reconstruct text already present after the cursor.
    @unique = grep {
        my $suffix = substr($_->{text}, length($prefix));
        length($suffix) == 0
            || substr($after_cursor, 0, length($suffix)) ne $suffix
    } @unique;

    if (!@unique) {
        return $self->dismiss();
    }

    $self->{results} = \@unique;
    $self->{prefix} = $prefix;

    # If we were idle, enter ghost state
    if ($self->{state} == STATE_IDLE) {
        $self->{ghost_index} = 0;
        $self->{state} = STATE_GHOST;
    }
    # If menu is open, keep it open but update results
    elsif ($self->{state} == STATE_MENU) {
        $self->{menu_index} = 0;
        $self->{menu_scroll} = 0;
    }
    # Ghost state: reset ghost index
    else {
        $self->{ghost_index} = 0;
    }

    return 1;
}

# Reset to idle
sub dismiss {
    my ($self) = @_;
    $self->{state} = STATE_IDLE;
    $self->{results} = [];
    $self->{prefix} = '';
    $self->{ghost_index} = 0;
    $self->{menu_index} = 0;
    $self->{menu_scroll} = 0;
    return 0;
}

# =============================================================================
# Accept / Navigate
# =============================================================================

# Returns the suffix text to insert, or a hashref for snippets:
#   { suffix => '...', body => '...', kind => 'snippet', prefix => '...' }
sub accept {
    my ($self) = @_;

    return '' unless $self->{state} != STATE_IDLE && @{$self->{results}};

    my $result;
    if ($self->{state} == STATE_MENU) {
        $result = $self->{results}[$self->{menu_index}];
    } else {
        $result = $self->{results}[$self->{ghost_index}];
    }

    # Record acceptance for RecentProvider
    if ($self->{_recent_provider} && $result->{text}) {
        $self->{_recent_provider}->record($result->{text});
    }

    my $prefix = $self->{prefix};

    # Snippet: return hashref with body for multi-line expansion
    if ($result->{kind} eq 'snippet' && defined $result->{body}) {
        my $info = {
            suffix => substr($result->{text}, length($prefix)),
            body   => $result->{body},
            kind   => 'snippet',
            prefix => $prefix,
        };
        $self->dismiss();
        return $info;
    }

    my $suffix = substr($result->{text}, length($prefix));
    $self->dismiss();
    return $suffix;
}

# Accept only the first character of the ghost text suffix.
# Returns the single character, or '' if nothing to accept.
# Keeps the completion active with updated prefix for remaining text.
sub accept_char {
    my ($self) = @_;

    return '' unless $self->{state} == STATE_GHOST && @{$self->{results}};

    my $result = $self->{results}[$self->{ghost_index}];
    my $prefix = $self->{prefix};
    my $suffix = substr($result->{text}, length($prefix));

    return '' unless length($suffix);

    my $char = substr($suffix, 0, 1);

    # Advance the prefix by one character so the ghost shows the remaining text
    $self->{prefix} = $prefix . $char;

    # If no more suffix remains, dismiss
    if (length($suffix) <= 1) {
        # Record acceptance for RecentProvider
        if ($self->{_recent_provider} && $result->{text}) {
            $self->{_recent_provider}->record($result->{text});
        }
        $self->dismiss();
    }

    return $char;
}

# Open dropdown menu from ghost state (or trigger + open)
sub open_menu {
    my ($self) = @_;
    return unless @{$self->{results}};
    $self->{state} = STATE_MENU;
    $self->{menu_index} = $self->{ghost_index};
    $self->{menu_scroll} = 0;
    $self->_ensure_menu_visible();
}

# Navigate dropdown up
sub menu_up {
    my ($self) = @_;
    return unless $self->{state} == STATE_MENU && @{$self->{results}};
    $self->{menu_index}--;
    $self->{menu_index} = $#{$self->{results}} if $self->{menu_index} < 0;
    $self->_ensure_menu_visible();
}

# Navigate dropdown down
sub menu_down {
    my ($self) = @_;
    return unless $self->{state} == STATE_MENU && @{$self->{results}};
    $self->{menu_index}++;
    $self->{menu_index} = 0 if $self->{menu_index} > $#{$self->{results}};
    $self->_ensure_menu_visible();
}

# Cycle ghost text to next alternative
sub cycle_next {
    my ($self) = @_;
    return unless $self->{state} == STATE_GHOST && @{$self->{results}};
    $self->{ghost_index} = ($self->{ghost_index} + 1) % scalar(@{$self->{results}});
}

# Cycle ghost text to previous alternative
sub cycle_prev {
    my ($self) = @_;
    return unless $self->{state} == STATE_GHOST && @{$self->{results}};
    $self->{ghost_index}--;
    $self->{ghost_index} = $#{$self->{results}} if $self->{ghost_index} < 0;
}

# =============================================================================
# State Query
# =============================================================================

sub is_active { $_[0]->{state} != STATE_IDLE }
sub is_ghost  { $_[0]->{state} == STATE_GHOST }
sub is_menu   { $_[0]->{state} == STATE_MENU }
sub state     { $_[0]->{state} }
sub prefix    { $_[0]->{prefix} }
sub results   { $_[0]->{results} }

# Returns hashref for ui.completion in render call
sub state_for_render {
    my ($self, $view, $doc) = @_;

    return undef unless $self->{state} != STATE_IDLE && @{$self->{results}};

    my $cursor_line = $view->cursor_line();
    my $cursor_col = $view->cursor_col();

    my $data = {
        state   => $self->{state},
        prefix  => $self->{prefix},
        cursor_line => $cursor_line,
        cursor_col  => $cursor_col,
    };

    if ($self->{state} == STATE_GHOST || $self->{state} == STATE_MENU) {
        # Ghost text: suffix of the selected result
        my $idx = ($self->{state} == STATE_MENU) ? $self->{menu_index} : $self->{ghost_index};
        my $result = $self->{results}[$idx];
        if ($result) {
            my $suffix = substr($result->{text}, length($self->{prefix}));
            $data->{ghost_text} = $suffix;
            $data->{ghost_kind} = $result->{kind};
        }
    }

    if ($self->{state} == STATE_MENU) {
        $data->{menu_items} = $self->{results};
        $data->{menu_index} = $self->{menu_index};
        $data->{menu_scroll} = $self->{menu_scroll};
        $data->{menu_max_visible} = $self->{_max_menu_visible};
    }

    return $data;
}

# =============================================================================
# Internal helpers
# =============================================================================

# Extract word prefix from line content at cursor position
sub _extract_prefix {
    my ($line, $col) = @_;

    return '' if $col <= 0 || $col > length($line);

    my $before = substr($line, 0, $col);

    # Scan backward for word characters
    if ($before =~ /([\w]+)$/) {
        return $1;
    }

    return '';
}

# Ensure selected menu item is visible in scroll window
sub _ensure_menu_visible {
    my ($self) = @_;
    my $idx = $self->{menu_index};
    my $scroll = $self->{menu_scroll};
    my $max_vis = $self->{_max_menu_visible};

    if ($idx < $scroll) {
        $self->{menu_scroll} = $idx;
    } elsif ($idx >= $scroll + $max_vis) {
        $self->{menu_scroll} = $idx - $max_vis + 1;
    }
}

1;
