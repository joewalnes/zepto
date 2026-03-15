package Zepto::Completion::BufferWordProvider;
# =============================================================================
# BufferWordProvider: Document word scanning for completions
# =============================================================================
#
# Scans the current document for unique word tokens (identifiers, function
# names, variables). Tracks frequency for scoring. Cache invalidates when
# document content version changes.
# =============================================================================

use strict;
use warnings;

use constant MAX_SCAN_LINES => 10000;

sub new {
    my ($class) = @_;
    return bless {
        _word_cache   => {},   # word => count
        _doc_version  => -1,   # content version when cache was built
        _doc_id       => '',   # document identity
    }, $class;
}

sub complete {
    my ($self, $context) = @_;

    my $doc = $context->{doc};
    return [] unless $doc;

    my $prefix = $context->{prefix};
    return [] unless defined $prefix && length($prefix) >= 2;

    # Rebuild cache if document changed
    $self->_rebuild_cache($doc);

    my $lc_prefix = lc($prefix);
    my $cursor_line = $context->{line_num};
    my @matches;

    my $words = $self->{_word_cache};
    for my $word (keys %$words) {
        next unless length($word) > length($prefix);
        my $lc_word = lc($word);
        next unless index($lc_word, $lc_prefix) == 0;  # Prefix match

        my $freq = $words->{$word};
        my $score = 50 + ($freq * 2);
        # Cap frequency bonus
        $score = 80 if $score > 80;
        # Exact case match bonus
        $score += 5 if index($word, $prefix) == 0;

        push @matches, {
            text  => $word,
            score => $score,
            kind  => 'word',
        };
    }

    return \@matches;
}

sub _rebuild_cache {
    my ($self, $doc) = @_;

    my $version = $doc->{_content_version} // 0;
    my $doc_id = "$doc";  # Object address as identity

    return if $version == $self->{_doc_version} && $doc_id eq $self->{_doc_id};

    $self->{_word_cache} = {};
    $self->{_doc_version} = $version;
    $self->{_doc_id} = $doc_id;

    my $line_count = $doc->line_count();
    my $max_lines = $line_count < MAX_SCAN_LINES ? $line_count : MAX_SCAN_LINES;

    my %words;
    for my $i (0 .. $max_lines - 1) {
        my $line = $doc->get_line_content($i);
        while ($line =~ /\b([a-zA-Z_]\w{2,})\b/g) {
            $words{$1}++;
        }
    }

    $self->{_word_cache} = \%words;
}

1;
