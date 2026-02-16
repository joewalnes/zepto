package Zepto::FindEngine;
# =============================================================================
# High-Performance Incremental Find Engine
# =============================================================================
#
# Design principles:
# 1. Viewport-first: Search visible lines synchronously (<5ms)
# 2. Background search: Full document search in interruptible chunks
# 3. Never block: Typing is instant, search happens async
# 4. Abort on change: New search term cancels in-flight work
#
# =============================================================================

use strict;
use warnings;
use Time::HiRes qw(time);

sub new {
    my ($class, %opts) = @_;

    return bless {
        document => $opts{document},

        # Callbacks
        on_viewport_ready => $opts{on_viewport_ready},
        on_progress       => $opts{on_progress},
        on_complete       => $opts{on_complete},

        # Search state
        search_term    => '',
        search_id      => 0,
        case_sensitive => 0,
        use_regex      => 0,

        # Results
        viewport_matches => [],
        all_matches      => [],

        # Background search state
        _bg_active       => 0,
        _bg_search_id    => 0,
        _bg_pos          => 0,       # Current position in text
        _bg_regex        => undef,
        _bg_matches      => [],
        _bg_text         => '',      # Cached full text for search
        _bg_line_offsets => [],      # [offset, ...] for each line start
    }, $class;
}

# =============================================================================
# Public API
# =============================================================================

# Search viewport immediately, start background search
# Returns viewport matches synchronously
sub search {
    my ($self, $term, $viewport_start, $viewport_end, %opts) = @_;

    $self->{search_term} = $term;
    $self->{case_sensitive} = $opts{case_sensitive} // 0;
    $self->{use_regex} = $opts{use_regex} // 0;
    $self->{search_id}++;

    # Abort any background search
    $self->{_bg_active} = 0;

    # Empty term = no matches
    if (!length($term)) {
        $self->{viewport_matches} = [];
        $self->{all_matches} = [];
        return [];
    }

    # Build regex once
    my $re = $self->_build_regex($term);
    return [] unless $re;

    # Cache full text and build line offset index ONCE
    my $doc = $self->{document};
    my $text = $doc->text();
    my @line_offsets = (0);
    my $pos = 0;
    while (($pos = index($text, "\n", $pos)) >= 0) {
        push @line_offsets, $pos + 1;
        $pos++;
    }
    $self->{_bg_text} = $text;
    $self->{_bg_line_offsets} = \@line_offsets;

    # Synchronous viewport search using cached text
    my $matches = $self->_search_range($re, $viewport_start, $viewport_end);
    $self->{viewport_matches} = $matches;

    # Notify viewport ready
    $self->{on_viewport_ready}->($matches) if $self->{on_viewport_ready};

    # Start background search
    $self->_start_background($re, $viewport_start, $viewport_end);

    return $matches;
}

# Continue background search for up to $max_ms milliseconds
# Returns progress info
sub tick {
    my ($self, $max_ms) = @_;
    $max_ms //= 10;

    return { done => 1, matches => 0, searched => 0, total => 0 }
        unless $self->{_bg_active};

    my $text = $self->{_bg_text};
    my $text_len = length($text);
    my $line_offsets = $self->{_bg_line_offsets};
    my $total_lines = scalar(@$line_offsets);
    my $deadline = time() + ($max_ms / 1000);
    my $re = $self->{_bg_regex};
    my $search_id = $self->{_bg_search_id};
    my $matches = $self->{_bg_matches};

    # Search by position in text, using pos() for continuation
    # NOTE: We use capturing group + pos() instead of $-[0]/$+[0] because
    # accessing @- and @+ inside a regex loop is ~100x slower in Perl
    pos($text) = $self->{_bg_pos};

    while ($text =~ /($re)/g) {
        # Check if search was aborted
        last if $self->{search_id} != $search_id;

        my $match_len = length($1);
        my $match_start = pos($text) - $match_len;

        # Convert offset to line/col using binary search
        my ($line, $col) = $self->_offset_to_line_col($match_start);

        # Skip viewport lines (already searched)
        unless ($line >= $self->{_bg_skip_start} && $line < $self->{_bg_skip_end}) {
            push @$matches, {
                line   => $line,
                col    => $col,
                length => $match_len,
            };
        }

        # Save position and check deadline periodically
        $self->{_bg_pos} = pos($text);
        last if time() >= $deadline;
    }

    # Check completion
    my $done = (!defined pos($text) || pos($text) >= $text_len)
            || ($self->{search_id} != $search_id);

    if ($done && $self->{search_id} == $search_id) {
        $self->{_bg_active} = 0;
        $self->{_bg_text} = '';  # Free memory
        # Merge viewport matches with background matches, sort by position
        $self->{all_matches} = $self->_merge_matches(
            $self->{viewport_matches},
            $matches
        );
        $self->{on_complete}->($self->{all_matches}) if $self->{on_complete};
    } elsif ($self->{on_progress}) {
        $self->{on_progress}->({
            matches  => scalar(@$matches) + scalar(@{$self->{viewport_matches}}),
            searched => $self->{_bg_pos},
            total    => $text_len,
        });
    }

    return {
        done     => $done,
        matches  => scalar(@$matches) + scalar(@{$self->{viewport_matches}}),
        searched => $self->{_bg_pos},
        total    => $text_len,
    };
}

# Abort current search
sub abort {
    my ($self) = @_;
    $self->{_bg_active} = 0;
    $self->{search_id}++;
}

# Check if background search is active
sub is_searching {
    my ($self) = @_;
    return $self->{_bg_active};
}

# Get current matches (viewport if bg not done, all if done)
sub matches {
    my ($self) = @_;
    return $self->{_bg_active} ? $self->{viewport_matches} : $self->{all_matches};
}

# Get viewport matches only
sub viewport_matches {
    my ($self) = @_;
    return $self->{viewport_matches};
}

# Get all matches (may be incomplete if bg search running)
sub all_matches {
    my ($self) = @_;
    return $self->{all_matches};
}

# Get match count
sub match_count {
    my ($self) = @_;
    if ($self->{_bg_active}) {
        return scalar(@{$self->{viewport_matches}}) + scalar(@{$self->{_bg_matches}});
    }
    return scalar(@{$self->{all_matches}});
}

# =============================================================================
# Replace Preview (Virtual - doesn't modify document)
# =============================================================================

# Get matches for a specific line from viewport matches
sub matches_for_line {
    my ($self, $line_num) = @_;
    return [ grep { $_->{line} == $line_num } @{$self->{viewport_matches}} ];
}

# Compute what a line would look like with replacements applied
# Returns: { text => "replaced text", highlights => [{start, end}, ...] }
sub preview_line {
    my ($self, $line_num, $replacement) = @_;

    my $doc = $self->{document};
    my $original = $doc->get_line_content($line_num);
    my $matches = $self->matches_for_line($line_num);

    return { text => $original, highlights => [] } unless @$matches;

    # Sort matches by column (should already be sorted, but ensure)
    my @sorted = sort { $a->{col} <=> $b->{col} } @$matches;

    # Build replaced text and track highlight positions
    my $result = '';
    my @highlights;
    my $last_end = 0;
    my $rep_len = length($replacement);

    for my $m (@sorted) {
        # Add text before this match
        $result .= substr($original, $last_end, $m->{col} - $last_end);

        # Track highlight position in result
        my $highlight_start = length($result);
        $result .= $replacement;
        push @highlights, {
            start => $highlight_start,
            end   => $highlight_start + $rep_len,
        };

        $last_end = $m->{col} + $m->{length};
    }

    # Add remaining text
    $result .= substr($original, $last_end);

    return { text => $result, highlights => \@highlights };
}

# Get preview info for visible lines (for renderer)
# Returns hash: line_num => { text => "...", highlights => [...] }
sub preview_viewport {
    my ($self, $replacement, $viewport_start, $viewport_end) = @_;

    my %preview;
    my $doc = $self->{document};
    my $total_lines = $doc->line_count();

    $viewport_end = $total_lines if $viewport_end > $total_lines;

    for my $line_num ($viewport_start .. $viewport_end - 1) {
        my $line_matches = $self->matches_for_line($line_num);
        next unless @$line_matches;

        $preview{$line_num} = $self->preview_line($line_num, $replacement);
    }

    return \%preview;
}

# =============================================================================
# Internal Methods
# =============================================================================

sub _build_regex {
    my ($self, $term) = @_;

    my $flags = $self->{case_sensitive} ? '' : 'i';
    my $pattern = $self->{use_regex} ? $term : quotemeta($term);

    my $re = eval { qr/(?$flags)$pattern/ };
    return $re;
}

# Search a range of lines using cached text (fast)
sub _search_range {
    my ($self, $re, $start_line, $end_line) = @_;

    my $text = $self->{_bg_text};
    my $line_offsets = $self->{_bg_line_offsets};
    my $total_lines = scalar(@$line_offsets);

    $start_line = 0 if $start_line < 0;
    $end_line = $total_lines if $end_line > $total_lines;

    # Get byte range for these lines
    my $start_pos = $line_offsets->[$start_line] // 0;
    my $end_pos = $end_line < $total_lines
        ? $line_offsets->[$end_line]
        : length($text);

    my @matches;

    # Extract the range and search it
    # NOTE: Use capturing group + pos() instead of $-[0]/$+[0] (100x faster)
    my $range_text = substr($text, $start_pos, $end_pos - $start_pos);
    pos($range_text) = 0;

    while ($range_text =~ /($re)/g) {
        my $match_len = length($1);
        my $match_offset = $start_pos + pos($range_text) - $match_len;
        my ($line, $col) = $self->_offset_to_line_col($match_offset);

        push @matches, {
            line   => $line,
            col    => $col,
            length => $match_len,
        };
    }

    return \@matches;
}

# Convert byte offset to (line, col) using binary search
sub _offset_to_line_col {
    my ($self, $offset) = @_;

    my $line_offsets = $self->{_bg_line_offsets};
    my $num_lines = scalar(@$line_offsets);

    return (0, 0) unless $num_lines;

    # Binary search for the line
    my ($lo, $hi) = (0, $num_lines - 1);
    while ($lo < $hi) {
        my $mid = int(($lo + $hi + 1) / 2);
        if ($line_offsets->[$mid] <= $offset) {
            $lo = $mid;
        } else {
            $hi = $mid - 1;
        }
    }

    my $line = $lo;
    my $col = $offset - $line_offsets->[$line];

    return ($line, $col);
}

sub _start_background {
    my ($self, $re, $viewport_start, $viewport_end) = @_;

    $self->{_bg_active} = 1;
    $self->{_bg_search_id} = $self->{search_id};
    $self->{_bg_pos} = 0;
    $self->{_bg_regex} = $re;
    $self->{_bg_matches} = [];
    $self->{_bg_skip_start} = $viewport_start;
    $self->{_bg_skip_end} = $viewport_end;
}

sub _merge_matches {
    my ($self, $viewport, $background) = @_;

    # Both arrays are sorted within themselves
    # Merge them maintaining sort order by (line, col)
    my @merged;
    my ($vi, $bi) = (0, 0);

    while ($vi < @$viewport && $bi < @$background) {
        my $v = $viewport->[$vi];
        my $b = $background->[$bi];

        if ($v->{line} < $b->{line} ||
            ($v->{line} == $b->{line} && $v->{col} <= $b->{col})) {
            push @merged, $v;
            $vi++;
        } else {
            push @merged, $b;
            $bi++;
        }
    }

    # Add remaining
    push @merged, @$viewport[$vi .. $#$viewport] if $vi < @$viewport;
    push @merged, @$background[$bi .. $#$background] if $bi < @$background;

    return \@merged;
}

1;
