package Zepto::Completion::RecentProvider;
# =============================================================================
# RecentProvider: Boost recently accepted completions
# =============================================================================
#
# Tracks the last N accepted completions and returns them with boosted
# scores when the user types a matching prefix again.
# =============================================================================

use strict;
use warnings;

use constant MAX_RECENT => 50;

sub new {
    my ($class) = @_;
    return bless {
        _recent => [],   # Most recent first
    }, $class;
}

sub record {
    my ($self, $text) = @_;
    return unless defined $text && length($text) >= 3;

    # Remove existing entry (dedup)
    my @filtered = grep { $_ ne $text } @{$self->{_recent}};

    # Prepend to front
    unshift @filtered, $text;

    # Truncate to max
    splice @filtered, MAX_RECENT if @filtered > MAX_RECENT;

    $self->{_recent} = \@filtered;
}

sub complete {
    my ($self, $context) = @_;

    my $prefix = $context->{prefix};
    return [] unless defined $prefix && length($prefix) >= 2;

    my $lc_prefix = lc($prefix);
    my @matches;
    my $recent = $self->{_recent};

    for my $i (0 .. $#$recent) {
        my $word = $recent->[$i];
        next unless length($word) > length($prefix);

        my $lc_word = lc($word);
        next unless index($lc_word, $lc_prefix) == 0;

        # Score: 85 base + recency bonus (more recent = higher)
        my $recency_bonus = int(10 * ($#$recent - $i + 1) / (@$recent || 1));
        my $score = 85 + $recency_bonus;

        # Exact case match bonus
        $score += 5 if index($word, $prefix) == 0;

        push @matches, {
            text  => $word,
            score => $score,
            kind  => 'recent',
        };
    }

    return \@matches;
}

1;
