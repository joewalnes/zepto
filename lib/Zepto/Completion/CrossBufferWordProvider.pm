package Zepto::Completion::CrossBufferWordProvider;
# =============================================================================
# CrossBufferWordProvider: Cross-buffer word scanning for completions
# =============================================================================
#
# Scans all open documents (tabs) for unique word tokens. Superset of
# BufferWordProvider — includes words from the active document plus all
# other open tabs. Words from the active document get a proximity bonus.
# =============================================================================

use strict;
use warnings;

use constant MAX_SCAN_LINES => 10000;

sub new {
    my ($class, %opts) = @_;
    return bless {
        tab_manager   => $opts{tab_manager},
        _word_cache   => {},   # word => count (merged across all docs)
        _active_words => {},   # words from active doc (for proximity boost)
        _versions     => {},   # doc_id => version
        _active_doc_id => '',  # track which doc was active
    }, $class;
}

sub complete {
    my ($self, $context) = @_;

    my $doc = $context->{doc};
    return [] unless $doc;

    my $prefix = $context->{prefix};
    return [] unless defined $prefix && length($prefix) >= 2;

    # Rebuild cache if any document changed
    $self->_rebuild_cache($doc);

    my $lc_prefix = lc($prefix);
    my @matches;

    my $words = $self->{_word_cache};
    my $active_words = $self->{_active_words};

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
        # Proximity boost for words from active document
        $score += 10 if $active_words->{$word};

        push @matches, {
            text  => $word,
            score => $score,
            kind  => 'word',
        };
    }

    return \@matches;
}

sub _rebuild_cache {
    my ($self, $active_doc) = @_;

    my $tm = $self->{tab_manager};
    return $self->_rebuild_single_doc($active_doc) unless $tm;

    my $tabs = $tm->tabs();
    my $active_doc_id = "$active_doc";

    # Check if any document version changed or active doc switched
    my $needs_rebuild = 0;
    if ($active_doc_id ne $self->{_active_doc_id}) {
        $needs_rebuild = 1;
    }

    unless ($needs_rebuild) {
        for my $tab (@$tabs) {
            my $doc = $tab->{document} or next;
            my $doc_id = "$doc";
            my $version = $doc->{_content_version} // 0;
            my $cached_version = $self->{_versions}{$doc_id} // -1;
            if ($version != $cached_version) {
                $needs_rebuild = 1;
                last;
            }
        }
    }

    return unless $needs_rebuild;

    # Rebuild from scratch
    my %all_words;
    my %active_words;
    my %versions;

    for my $tab (@$tabs) {
        my $doc = $tab->{document} or next;
        my $doc_id = "$doc";
        my $version = $doc->{_content_version} // 0;
        $versions{$doc_id} = $version;

        my $is_active = ($doc_id eq $active_doc_id);
        my $line_count = $doc->line_count();
        my $max_lines = $line_count < MAX_SCAN_LINES ? $line_count : MAX_SCAN_LINES;

        for my $i (0 .. $max_lines - 1) {
            my $line = $doc->get_line_content($i);
            while ($line =~ /\b([a-zA-Z_]\w{2,})\b/g) {
                $all_words{$1}++;
                $active_words{$1} = 1 if $is_active;
            }
        }
    }

    $self->{_word_cache} = \%all_words;
    $self->{_active_words} = \%active_words;
    $self->{_versions} = \%versions;
    $self->{_active_doc_id} = $active_doc_id;
}

# Fallback: no tab_manager, scan single doc (like BufferWordProvider)
sub _rebuild_single_doc {
    my ($self, $doc) = @_;

    my $version = $doc->{_content_version} // 0;
    my $doc_id = "$doc";

    return if ($self->{_versions}{$doc_id} // -1) == $version
           && $doc_id eq $self->{_active_doc_id};

    my %words;
    my $line_count = $doc->line_count();
    my $max_lines = $line_count < MAX_SCAN_LINES ? $line_count : MAX_SCAN_LINES;

    for my $i (0 .. $max_lines - 1) {
        my $line = $doc->get_line_content($i);
        while ($line =~ /\b([a-zA-Z_]\w{2,})\b/g) {
            $words{$1}++;
        }
    }

    $self->{_word_cache} = \%words;
    $self->{_active_words} = \%words;
    $self->{_versions} = { $doc_id => $version };
    $self->{_active_doc_id} = $doc_id;
}

1;
