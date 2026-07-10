package Zepto::Editor::TabManager;
# =============================================================================
# TabManager: Manages ordered list of open tabs with MRU tracking
# =============================================================================

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;
    return bless {
        tabs           => [],    # Array of tab hashes
        active_index   => 0,     # Currently displayed tab
        mru_stack      => [],    # Tab indices ordered by most-recently-used
        next_untitled  => 1,     # Counter for [untitled-N] naming
        tab_scroll_offset => 0,  # First visible tab when tabs overflow
    }, $class;
}

# --- Tab creation and removal ---

sub add_tab {
    my ($self, %opts) = @_;

    my $tab = {
        document      => $opts{document},
        view          => $opts{view},
        find_engine   => $opts{find_engine},
        highlighter   => $opts{highlighter},
        file_path     => $opts{file_path},
        untitled_name => $opts{untitled_name},

        # Per-tab search state
        search_term         => '',
        search_replace      => '',
        find_input          => '',
        find_input_cursor   => 0,
        find_current        => 0,
        find_regex          => 1,
        find_case           => 0,
        find_replace_input  => '',
        find_replace_cursor => 0,
        find_replace_active => 0,
        find_focus          => 'find',
        find_replace_all    => 1,
        find_matches        => [],
        find_replaced       => [],
        find_replace_preview => undef,
    };

    push @{$self->{tabs}}, $tab;
    my $idx = $#{ $self->{tabs} };

    # Make new tab active and push to MRU front
    $self->{active_index} = $idx;
    unshift @{$self->{mru_stack}}, $idx;

    return $idx;
}

sub remove_tab {
    my ($self, $index) = @_;

    my $tabs = $self->{tabs};
    return unless $index >= 0 && $index < @$tabs;

    splice @$tabs, $index, 1;

    # Update MRU stack: remove the index, adjust remaining
    my @new_mru;
    for my $i (@{$self->{mru_stack}}) {
        next if $i == $index;
        push @new_mru, $i > $index ? $i - 1 : $i;
    }
    $self->{mru_stack} = \@new_mru;

    # Adjust active index
    if (@$tabs == 0) {
        $self->{active_index} = 0;
    }
    elsif ($self->{active_index} > $index) {
        $self->{active_index}--;
    }
    elsif ($self->{active_index} >= @$tabs) {
        $self->{active_index} = @$tabs - 1;
    }

    return;
}

# --- Active tab accessors ---

sub active_index { $_[0]->{active_index} }

sub active_tab {
    my ($self) = @_;
    return $self->{tabs}[$self->{active_index}];
}

sub active_doc {
    my ($self) = @_;
    my $tab = $self->active_tab();
    return $tab ? $tab->{document} : undef;
}

sub active_view {
    my ($self) = @_;
    my $tab = $self->active_tab();
    return $tab ? $tab->{view} : undef;
}

sub active_find_engine {
    my ($self) = @_;
    my $tab = $self->active_tab();
    return $tab ? $tab->{find_engine} : undef;
}

sub active_highlighter {
    my ($self) = @_;
    my $tab = $self->active_tab();
    return $tab ? $tab->{highlighter} : undef;
}

sub active_file_path {
    my ($self) = @_;
    my $tab = $self->active_tab();
    return $tab ? $tab->{file_path} : undef;
}


# --- Tab switching ---

sub set_active {
    my ($self, $index) = @_;
    return unless $index >= 0 && $index < @{$self->{tabs}};

    $self->{active_index} = $index;

    # Update MRU: remove if present, push to front
    my @new_mru = grep { $_ != $index } @{$self->{mru_stack}};
    unshift @new_mru, $index;
    $self->{mru_stack} = \@new_mru;
}

sub mru_previous {
    my ($self) = @_;
    # MRU[0] is current active, MRU[1] is previous
    my $mru = $self->{mru_stack};
    return $mru->[1] if @$mru > 1;
    return $self->{active_index};
}

# --- Tab queries ---

sub tab_count { scalar @{$_[0]->{tabs}} }

sub tab_at {
    my ($self, $index) = @_;
    return $self->{tabs}[$index];
}

sub tabs { $_[0]->{tabs} }

sub find_tab_by_path {
    my ($self, $path) = @_;
    return undef unless defined $path;

    # Normalize to absolute path for comparison
    my $abs_path = File::Spec->rel2abs($path);

    for my $i (0 .. $#{$self->{tabs}}) {
        my $tab_path = $self->{tabs}[$i]{file_path};
        next unless defined $tab_path;
        my $abs_tab = File::Spec->rel2abs($tab_path);
        return $i if $abs_path eq $abs_tab;
    }
    return undef;
}

# --- Untitled naming ---

sub next_untitled_name {
    my ($self) = @_;
    my $n = $self->{next_untitled}++;
    return $n == 1 ? '[untitled]' : "[untitled-$n]";
}

# --- Tab reordering ---

sub move_tab {
    my ($self, $from, $to) = @_;
    my $tabs = $self->{tabs};
    return unless $from >= 0 && $from < @$tabs;
    return unless $to >= 0 && $to < @$tabs;
    return if $from == $to;

    my $tab = splice @$tabs, $from, 1;
    splice @$tabs, $to, 0, $tab;

    # Update active_index to follow the moved tab
    if ($self->{active_index} == $from) {
        $self->{active_index} = $to;
    }
    elsif ($from < $to) {
        # Tab moved right: indices between (from, to] shift left
        $self->{active_index}-- if $self->{active_index} > $from && $self->{active_index} <= $to;
    }
    else {
        # Tab moved left: indices between [to, from) shift right
        $self->{active_index}++ if $self->{active_index} >= $to && $self->{active_index} < $from;
    }

    # Rebuild MRU stack with new indices
    my @new_mru;
    for my $idx (@{$self->{mru_stack}}) {
        if ($idx == $from) {
            push @new_mru, $to;
        }
        elsif ($from < $to) {
            push @new_mru, ($idx > $from && $idx <= $to) ? $idx - 1 : $idx;
        }
        else {
            push @new_mru, ($idx >= $to && $idx < $from) ? $idx + 1 : $idx;
        }
    }
    $self->{mru_stack} = \@new_mru;
}

# --- Rendering support ---

sub tabs_for_render {
    my ($self) = @_;

    my @tabs = @{$self->{tabs}};
    my @result;

    # Detect duplicate basenames
    my %name_count;
    for my $tab (@tabs) {
        my $name = $self->_tab_display_name($tab);
        $name_count{$name}++;
    }

    for my $i (0 .. $#tabs) {
        my $tab = $tabs[$i];
        my $name = $self->_tab_display_name($tab);
        my $display = $name;

        # Disambiguate duplicates with parent directory
        if (($name_count{$name} // 0) > 1 && defined $tab->{file_path}) {
            my ($parent) = $tab->{file_path} =~ m{([^/]+)/[^/]+$};
            $display = "$parent/$name" if $parent;
        }

        # Check for VCS changes (file has uncommitted git changes)
        my $has_vcs_changes = 0;
        if ($tab->{document} && $tab->{document}->has_vcs()) {
            my $diff = $tab->{document}->vcs_diff();
            if ($diff) {
                $has_vcs_changes = 1 if @{$diff->{added} // []}
                                     || @{$diff->{modified} // []}
                                     || @{$diff->{deleted} // []};
            }
        }

        push @result, {
            display_name    => $display,
            file_path       => $tab->{file_path},
            is_dirty        => $tab->{document} ? $tab->{document}->is_dirty() : 0,
            has_vcs_changes => $has_vcs_changes,
            index           => $i,
        };
    }

    return \@result;
}

sub _tab_display_name {
    my ($self, $tab) = @_;
    if ($tab->{untitled_name}) {
        return $tab->{untitled_name};
    }
    if ($tab->{document} && $tab->{document}->filename()) {
        return $tab->{document}->filename();
    }
    if ($tab->{file_path}) {
        my ($name) = $tab->{file_path} =~ m{([^/]+)$};
        return $name // $tab->{file_path};
    }
    return '[untitled]';
}

# --- Scroll offset for tab overflow ---

sub tab_scroll_offset { $_[0]->{tab_scroll_offset} }

sub set_tab_scroll_offset {
    my ($self, $offset) = @_;
    $self->{tab_scroll_offset} = $offset;
}

BEGIN {
    require File::Spec;
}

1;
