package Zepto::Completion::KeywordProvider;
# =============================================================================
# KeywordProvider: Language keyword completions from syntax grammars
# =============================================================================

use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {
        _cache => {},  # language => \@keywords
    }, $class;
}

sub complete {
    my ($self, $context) = @_;

    my $language = $context->{language};
    return [] unless $language;

    my $prefix = $context->{prefix};
    return [] unless defined $prefix && length($prefix) >= 2;

    # Get keyword list (cached per language)
    my $keywords = $self->_get_keywords($language, $context->{highlighter});
    return [] unless $keywords && @$keywords;

    my $lc_prefix = lc($prefix);
    my @matches;

    for my $kw (@$keywords) {
        next unless length($kw) > length($prefix);
        my $lc_kw = lc($kw);
        next unless index($lc_kw, $lc_prefix) == 0;  # Prefix match

        my $score = 100;
        # Exact case match bonus
        $score += 10 if index($kw, $prefix) == 0;
        # Shorter keywords score slightly higher (more common)
        $score += int(20 / (length($kw) + 1));

        push @matches, {
            text  => $kw,
            score => $score,
            kind  => 'keyword',
        };
    }

    return \@matches;
}

sub _get_keywords {
    my ($self, $language, $highlighter) = @_;

    return $self->{_cache}{$language} if exists $self->{_cache}{$language};

    my $keywords = [];
    if ($highlighter) {
        my $grammar = $highlighter->{grammar};
        if ($grammar && $grammar->can('keyword_list')) {
            $keywords = $grammar->keyword_list() // [];
        }
    }

    $self->{_cache}{$language} = $keywords;
    return $keywords;
}

1;
