package Zepto::FilePicker;
# =============================================================================
# File Picker - Fuzzy file finder for Zepto Editor
# =============================================================================
#
# Provides file discovery and fuzzy matching for the open file dialog.
# Uses configurable ignore patterns from Zepto::Config.
#
# =============================================================================

use strict;
use warnings;
use Zepto::Config;

# Natural sort: "file2" before "file10", case-insensitive
sub _natural_cmp {
    my ($a, $b) = @_;
    my @a_parts = map { /^\d+$/ ? $_ : lc($_) } split(/(\d+)/, $a);
    my @b_parts = map { /^\d+$/ ? $_ : lc($_) } split(/(\d+)/, $b);
    for my $i (0 .. ($#a_parts < $#b_parts ? $#a_parts : $#b_parts)) {
        my $cmp;
        if ($a_parts[$i] =~ /^\d+$/ && $b_parts[$i] =~ /^\d+$/) {
            $cmp = $a_parts[$i] <=> $b_parts[$i];
        } else {
            $cmp = $a_parts[$i] cmp $b_parts[$i];
        }
        return $cmp if $cmp;
    }
    return @a_parts <=> @b_parts;
}

# =============================================================================
# Constructor
# =============================================================================

sub new {
    my ($class, %opts) = @_;

    my $base_dir = $opts{base_dir} // '.';

    my $self = bless {
        base_dir    => $base_dir,
        all_files   => [],      # All discovered files
        filtered    => [],      # Filtered and sorted results
        query       => '',      # Current search query
        selected    => 0,       # Selected index in filtered list
        scroll      => 0,       # Scroll offset
        on_select   => $opts{on_select},   # Callback when file selected
        on_cancel   => $opts{on_cancel},   # Callback when cancelled
    }, $class;

    # Discover files immediately
    $self->_discover_files();
    $self->_apply_filter();

    return $self;
}

# =============================================================================
# File Discovery
# =============================================================================

sub _discover_files {
    my ($self) = @_;

    my $base = $self->{base_dir};
    my $max_files = Zepto::Config::max_files();
    my $max_depth = Zepto::Config::max_depth();
    my %skip = Zepto::Config::skip_directories_hash();

    my @files;

    my $walk;
    $walk = sub {
        my ($dir, $depth) = @_;
        return if $depth > $max_depth;
        return if @files >= $max_files;

        opendir(my $dh, $dir) or return;
        my @entries = readdir($dh);
        closedir($dh);

        for my $entry (sort { _natural_cmp($a, $b) } @entries) {
            next if $entry eq '.' || $entry eq '..';
            return if @files >= $max_files;

            my $path = "$dir/$entry";

            if (-d $path) {
                next if $skip{$entry};
                $walk->($path, $depth + 1);
            }
            elsif (-f $path && -r $path) {
                # Make path relative to base
                my $rel = $path;
                $rel =~ s{^\Q$base\E/?}{};
                push @files, $rel;
            }
        }
    };

    $walk->($base, 0);

    $self->{all_files} = \@files;
}

# =============================================================================
# Fuzzy Matching
# =============================================================================

sub _fuzzy_score {
    my ($query, $path) = @_;

    return 0 unless length($query);

    my $lq = lc $query;
    my $lp = lc $path;

    my $qi = 0;
    my $score = 0;
    my $consecutive = 0;
    my $last_match = -2;

    for my $pi (0 .. length($lp) - 1) {
        next unless $qi < length($lq);

        my $qchar = substr($lq, $qi, 1);
        my $pchar = substr($lp, $pi, 1);

        next unless $pchar eq $qchar;

        $score += 1;

        # Consecutive character bonus
        if ($pi == $last_match + 1) {
            $consecutive++;
            $score += $consecutive * 3;
        } else {
            $consecutive = 0;
        }

        # Word boundary bonus (after / . _ -)
        if ($pi == 0 || substr($lp, $pi - 1, 1) =~ m{[/._-]}) {
            $score += 10;
        }

        $last_match = $pi;
        $qi++;
    }

    # Not all query chars matched
    return -1 if $qi < length($lq);

    # Filename-start bonus
    my ($fname) = $path =~ m{([^/]+)$};
    if (defined $fname && index(lc $fname, $lq) == 0) {
        $score += 15;
    }

    # Prefer shorter paths (slight penalty for length)
    $score -= length($path) * 0.1;

    return $score;
}

sub _apply_filter {
    my ($self) = @_;

    my $query = $self->{query};
    my @files = @{$self->{all_files}};

    if (!length($query)) {
        # No query - show all files sorted alphabetically
        $self->{filtered} = [sort { _natural_cmp($a, $b) } @files];
    } else {
        # Score and filter
        my @scored;
        for my $file (@files) {
            my $score = _fuzzy_score($query, $file);
            push @scored, [$file, $score] if $score >= 0;
        }

        # Sort by score descending
        @scored = sort { $b->[1] <=> $a->[1] } @scored;

        $self->{filtered} = [map { $_->[0] } @scored];
    }

    # Reset selection to top
    $self->{selected} = 0;
    $self->{scroll} = 0;
}

# =============================================================================
# Query Manipulation
# =============================================================================

sub set_query {
    my ($self, $query) = @_;
    $self->{query} = $query;
    $self->_apply_filter();
}

sub append_char {
    my ($self, $char) = @_;
    $self->{query} .= $char;
    $self->_apply_filter();
}

sub backspace {
    my ($self) = @_;
    if (length($self->{query}) > 0) {
        $self->{query} = substr($self->{query}, 0, -1);
        $self->_apply_filter();
    }
}

# =============================================================================
# Navigation
# =============================================================================

sub move_up {
    my ($self) = @_;
    if ($self->{selected} > 0) {
        $self->{selected}--;
        $self->_ensure_visible();
    }
}

sub move_down {
    my ($self) = @_;
    my $max = $#{$self->{filtered}};
    if ($self->{selected} < $max) {
        $self->{selected}++;
        $self->_ensure_visible();
    }
}

sub page_up {
    my ($self, $visible_rows) = @_;
    $visible_rows //= Zepto::Config::picker_visible_rows();
    $self->{selected} -= $visible_rows;
    $self->{selected} = 0 if $self->{selected} < 0;
    $self->_ensure_visible();
}

sub page_down {
    my ($self, $visible_rows) = @_;
    $visible_rows //= Zepto::Config::picker_visible_rows();
    my $max = $#{$self->{filtered}};
    $self->{selected} += $visible_rows;
    $self->{selected} = $max if $self->{selected} > $max;
    $self->_ensure_visible();
}

sub select_index {
    my ($self, $index) = @_;
    my $max = $#{$self->{filtered}};
    return if $index < 0 || $index > $max;
    $self->{selected} = $index;
}

sub _ensure_visible {
    my ($self) = @_;
    my $visible = Zepto::Config::picker_visible_rows();

    if ($self->{selected} < $self->{scroll}) {
        $self->{scroll} = $self->{selected};
    }
    elsif ($self->{selected} >= $self->{scroll} + $visible) {
        $self->{scroll} = $self->{selected} - $visible + 1;
    }
}

# =============================================================================
# Selection
# =============================================================================

sub selected_file {
    my ($self) = @_;
    my $idx = $self->{selected};
    return undef unless $idx >= 0 && $idx <= $#{$self->{filtered}};
    return $self->{filtered}[$idx];
}

sub confirm {
    my ($self) = @_;
    my $file = $self->selected_file();
    if (defined $file && $self->{on_select}) {
        $self->{on_select}->($file);
    }
}

sub cancel {
    my ($self) = @_;
    if ($self->{on_cancel}) {
        $self->{on_cancel}->();
    }
}

# =============================================================================
# Accessors
# =============================================================================

sub query       { $_[0]->{query} }
sub filtered    { $_[0]->{filtered} }
sub selected    { $_[0]->{selected} }
sub scroll      { $_[0]->{scroll} }
sub total_files { scalar @{$_[0]->{all_files}} }
sub filtered_count { scalar @{$_[0]->{filtered}} }

sub set_scroll {
    my ($self, $scroll) = @_;
    $self->{scroll} = $scroll;
}

1;
