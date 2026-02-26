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

# Get number of capture groups in current regex pattern
sub capture_group_count {
    my ($self) = @_;
    return 0 unless $self->{use_regex};
    return $self->_count_capture_groups($self->{search_term});
}

# Return compiled regex for capture group extraction (used by Renderer)
sub capture_regex {
    my ($self) = @_;
    return undef unless $self->{use_regex};
    return $self->_build_regex($self->{search_term});
}

# =============================================================================
# Capture Group Replacement
# =============================================================================

# Expand capture references ($0, $1, ...) in replacement for a specific match
# Returns the expanded replacement string
sub expand_replacement_for_match {
    my ($self, $match, $replacement) = @_;

    # No expansion in literal mode
    return $replacement unless $self->{use_regex};

    # Quick check: does replacement contain any $ references?
    return $replacement unless $replacement =~ /\$/;

    # Get the matched text from the document
    my $doc = $self->{document};
    my $line_content = $doc->get_line_content($match->{line});
    my $matched_text = substr($line_content, $match->{col}, $match->{length});

    # Build regex (without the ($re) wrapper used in search loop)
    my $re = $self->_build_regex($self->{search_term});
    return $replacement unless $re;

    # Extract captures and expand
    my $captures = $self->_extract_captures($matched_text, $re);
    return $self->_expand_replacement($replacement, $matched_text, $captures);
}

# Expand captures using raw text and pre-built regex (for _replace_all fast path)
sub expand_replacement_for_text {
    my ($self, $matched_text, $replacement, $re) = @_;

    my $captures = $self->_extract_captures($matched_text, $re);
    return $self->_expand_replacement($replacement, $matched_text, $captures);
}

# Map capture group positions within expanded replacement text
# Returns arrayref of { start, end, group } with positions relative to base_offset
sub _map_replacement_capture_positions {
    my ($self, $replacement, $matched_text, $captures, $base_offset) = @_;

    my @regions;
    my $pos = 0;  # position in expanded output
    my $i = 0;
    my $len = length($replacement);

    while ($i < $len) {
        my $ch = substr($replacement, $i, 1);

        if ($ch eq '$') {
            if ($i + 1 < $len) {
                my $next = substr($replacement, $i + 1, 1);
                if ($next eq '$') {
                    $pos++;
                    $i += 2;
                    next;
                }
                if ($next =~ /[0-9]/) {
                    my $num_str = '';
                    my $j = $i + 1;
                    while ($j < $len && substr($replacement, $j, 1) =~ /[0-9]/) {
                        $num_str .= substr($replacement, $j, 1);
                        $j++;
                    }
                    my $num = int($num_str);
                    my $text;
                    if ($num == 0) {
                        $text = $matched_text;
                        # $0 = full match, no group color
                    } elsif ($num <= scalar @$captures && defined $captures->[$num - 1]) {
                        $text = $captures->[$num - 1];
                        if (length($text) > 0) {
                            push @regions, {
                                start => $base_offset + $pos,
                                end   => $base_offset + $pos + length($text),
                                group => $num,
                            };
                        }
                    } else {
                        $text = '$' . $num_str;
                    }
                    $pos += length($text // '');
                    $i = $j;
                    next;
                }
            }
            $pos++;
            $i++;
        } else {
            $pos++;
            $i++;
        }
    }

    return \@regions;
}

# Extract capture group positions within matched text (for highlighting)
# Returns arrayref of { start, length, group } relative to match start
sub extract_capture_positions {
    my ($self, $match) = @_;

    return [] unless $self->{use_regex};

    my $doc = $self->{document};
    my $line_content = $doc->get_line_content($match->{line});
    my $matched_text = substr($line_content, $match->{col}, $match->{length});

    my $re = $self->_build_regex($self->{search_term});
    return [] unless $re;

    return $self->_extract_capture_positions($matched_text, $re);
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
# Returns: { text => "replaced text", highlights => [{start, end}, ...],
#            capture_regions => [{start, end, group}, ...] }
sub preview_line {
    my ($self, $line_num, $replacement) = @_;

    my $doc = $self->{document};
    my $original = $doc->get_line_content($line_num);
    my $matches = $self->matches_for_line($line_num);

    return { text => $original, highlights => [], capture_regions => [] } unless @$matches;

    # Sort matches by column (should already be sorted, but ensure)
    my @sorted = sort { $a->{col} <=> $b->{col} } @$matches;

    # Build replaced text and track highlight positions
    my $result = '';
    my @highlights;
    my @capture_regions;
    my $last_end = 0;

    # Check if we need to compute capture regions
    my $capture_regex = $self->capture_regex();
    my $has_captures = $capture_regex && $self->capture_group_count() > 0
                       && $replacement =~ /\$/;

    for my $m (@sorted) {
        # Add text before this match
        $result .= substr($original, $last_end, $m->{col} - $last_end);

        # Expand capture references if in regex mode
        my $expanded = $self->expand_replacement_for_match($m, $replacement);

        # Track highlight position in result
        my $highlight_start = length($result);

        # Compute capture group positions within the replacement text
        if ($has_captures) {
            my $matched_text = substr($original, $m->{col}, $m->{length});
            my $captures = $self->_extract_captures($matched_text, $capture_regex);
            my $regions = $self->_map_replacement_capture_positions(
                $replacement, $matched_text, $captures, $highlight_start
            );
            push @capture_regions, @$regions;
        }

        $result .= $expanded;
        push @highlights, {
            start => $highlight_start,
            end   => $highlight_start + length($expanded),
        };

        $last_end = $m->{col} + $m->{length};
    }

    # Add remaining text
    $result .= substr($original, $last_end);

    return { text => $result, highlights => \@highlights, capture_regions => \@capture_regions };
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

# Count capturing groups in a regex pattern string
sub _count_capture_groups {
    my ($self, $pattern) = @_;

    my $count = 0;
    my $i = 0;
    my $len = length($pattern);

    while ($i < $len) {
        my $ch = substr($pattern, $i, 1);

        # Skip escaped characters
        if ($ch eq '\\') {
            $i += 2;
            next;
        }

        # Skip character classes entirely (parens inside don't count)
        if ($ch eq '[') {
            $i++;
            # Handle negation
            $i++ if $i < $len && substr($pattern, $i, 1) eq '^';
            # Handle ] as first char in class (literal)
            $i++ if $i < $len && substr($pattern, $i, 1) eq ']';
            while ($i < $len && substr($pattern, $i, 1) ne ']') {
                $i++ if substr($pattern, $i, 1) eq '\\';
                $i++;
            }
            $i++;  # Skip closing ]
            next;
        }

        if ($ch eq '(') {
            if ($i + 1 < $len && substr($pattern, $i + 1, 1) eq '?') {
                # Check for named capture (?<name>...) which IS capturing
                if ($i + 2 < $len && substr($pattern, $i + 2, 1) eq '<') {
                    # (?<= and (?<! are lookbehind, not capturing
                    # (?<name> where name starts with letter/underscore IS capturing
                    if ($i + 3 < $len && substr($pattern, $i + 3, 1) =~ /[A-Za-z_]/) {
                        $count++;
                    }
                }
                elsif ($i + 2 < $len && substr($pattern, $i + 2, 1) eq 'P'
                    && $i + 3 < $len && substr($pattern, $i + 3, 1) eq '<') {
                    # (?P<name>...) - Python-style named capture, also works in Perl
                    $count++;
                }
                # All other (?...) forms are non-capturing
            } else {
                # Plain ( = capturing group
                $count++;
            }
        }

        $i++;
    }

    return $count;
}

# Extract capture group values from matched text
# Returns arrayref of capture strings
sub _extract_captures {
    my ($self, $matched_text, $re) = @_;

    my @captures;
    if ($matched_text =~ /$re/) {
        no strict 'refs';
        for my $i (1 .. 20) {
            last unless defined ${ $i };
            push @captures, ${ $i };
        }
    }

    return \@captures;
}

# Extract capture group positions within matched text
# Returns arrayref of { start, length, group } relative to match start
sub _extract_capture_positions {
    my ($self, $matched_text, $re) = @_;

    my @positions;
    if ($matched_text =~ /$re/) {
        for my $i (1 .. $#+) {
            if (defined $-[$i]) {
                push @positions, {
                    start  => $-[$i],
                    length => $+[$i] - $-[$i],
                    group  => $i,
                };
            }
        }
    }

    return \@positions;
}

# Expand capture references in a replacement template
# $0 = full match, $1 = first capture, etc.
# $$ = literal $
sub _expand_replacement {
    my ($self, $replacement, $matched_text, $captures) = @_;

    my $result = '';
    my $i = 0;
    my $len = length($replacement);

    while ($i < $len) {
        my $ch = substr($replacement, $i, 1);

        if ($ch eq '$') {
            if ($i + 1 < $len) {
                my $next = substr($replacement, $i + 1, 1);

                if ($next eq '$') {
                    # $$ -> literal $
                    $result .= '$';
                    $i += 2;
                    next;
                }

                if ($next =~ /[0-9]/) {
                    # Collect all consecutive digits
                    my $num_str = '';
                    my $j = $i + 1;
                    while ($j < $len && substr($replacement, $j, 1) =~ /[0-9]/) {
                        $num_str .= substr($replacement, $j, 1);
                        $j++;
                    }
                    my $num = int($num_str);

                    if ($num == 0) {
                        $result .= $matched_text;
                    } elsif ($num <= scalar @$captures) {
                        $result .= $captures->[$num - 1];
                    } else {
                        # Beyond capture count: leave as literal
                        $result .= '$' . $num_str;
                    }
                    $i = $j;
                    next;
                }
            }
            # $ at end or $ followed by non-digit/non-$ -> literal $
            $result .= '$';
            $i++;
        } else {
            $result .= $ch;
            $i++;
        }
    }

    return $result;
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
