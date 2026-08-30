package Zepto::Completion::CrossBufferWordProvider;
# =============================================================================
# CrossBufferWordProvider: Cross-buffer word scanning for completions
# =============================================================================
#
# Scans all open documents (tabs) for unique word tokens. Superset of
# BufferWordProvider — includes words from the active document plus all
# other open tabs. Words from the active document get a proximity bonus.
#
# Caching: each open document has its OWN word-frequency cache, keyed by
# that document's content_version (see _doc_words / _doc_versions below).
# On a trigger, only documents whose version changed since the last scan
# get rescanned (the line-by-line regex pass, up to MAX_SCAN_LINES lines
# each) — untouched tabs are never rescanned. Closed tabs' cache entries
# are dropped. A merged view (word => total count across all open docs)
# is recomputed by summing the per-document caches; that merge is O(total
# unique words), not O(total lines), so it's cheap to redo whenever
# anything changed rather than trying to maintain it incrementally.
# =============================================================================

use strict;
use warnings;

use constant MAX_SCAN_LINES => 10000;

sub new {
    my ($class, %opts) = @_;
    return bless {
        tab_manager    => $opts{tab_manager},
        _doc_words     => {},   # doc_id => { word => count } (per-document cache)
        _doc_versions  => {},   # doc_id => content_version last scanned
        _word_cache    => {},   # word => count (merged across all docs; derived)
        _active_words  => {},   # words from active doc (for proximity boost)
        _active_doc_id => '',   # track which doc was active
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

    my $doc_words = $self->{_doc_words};
    my $doc_versions = $self->{_doc_versions};

    my %seen_ids;
    my $any_changed = ($active_doc_id ne $self->{_active_doc_id}) ? 1 : 0;

    # Rescan only the documents whose content_version changed since we
    # last scanned them. Each doc's word-frequency hash is cached
    # independently, so an edit in one tab never touches another tab's
    # cache entry.
    for my $tab (@$tabs) {
        my $doc = $tab->{document} or next;
        my $doc_id = "$doc";
        $seen_ids{$doc_id} = 1;

        my $version = $doc->{_content_version} // 0;
        my $cached_version = $doc_versions->{$doc_id} // -1;
        next if $version == $cached_version;

        $doc_words->{$doc_id} = $self->_scan_doc($doc);
        $doc_versions->{$doc_id} = $version;
        $any_changed = 1;
    }

    # Drop cache entries for tabs that have since been closed.
    for my $doc_id (keys %$doc_words) {
        next if $seen_ids{$doc_id};
        delete $doc_words->{$doc_id};
        delete $doc_versions->{$doc_id};
        $any_changed = 1;
    }

    return unless $any_changed;

    # Cheap merge across the (already-cached) per-document word hashes —
    # this is O(total unique words), not O(total lines), so redoing it
    # whenever anything changed is fine even though scanning is skipped
    # for unchanged docs.
    my %all_words;
    for my $words (values %$doc_words) {
        while (my ($word, $count) = each %$words) {
            $all_words{$word} += $count;
        }
    }

    $self->{_word_cache} = \%all_words;
    $self->{_active_words} = { map { $_ => 1 } keys %{ $doc_words->{$active_doc_id} || {} } };
    $self->{_active_doc_id} = $active_doc_id;
}

# Fallback: no tab_manager, scan single doc (like BufferWordProvider)
sub _rebuild_single_doc {
    my ($self, $doc) = @_;

    my $version = $doc->{_content_version} // 0;
    my $doc_id = "$doc";

    return if ($self->{_doc_versions}{$doc_id} // -1) == $version
           && $doc_id eq $self->{_active_doc_id};

    my $words = $self->_scan_doc($doc);

    $self->{_doc_words} = { $doc_id => $words };
    $self->{_doc_versions} = { $doc_id => $version };
    $self->{_word_cache} = $words;
    $self->{_active_words} = $words;
    $self->{_active_doc_id} = $doc_id;
}

# Scan a single document's lines for word tokens. Returns a fresh
# word => count hashref. This is the only expensive (line-count-scaling)
# operation in the provider; everything else operates on already-scanned
# per-document hashes.
sub _scan_doc {
    my ($self, $doc) = @_;

    my %words;
    my $line_count = $doc->line_count();
    my $max_lines = $line_count < MAX_SCAN_LINES ? $line_count : MAX_SCAN_LINES;

    for my $i (0 .. $max_lines - 1) {
        my $line = $doc->get_line_content($i);
        while ($line =~ /\b([a-zA-Z_]\w{2,})\b/g) {
            $words{$1}++;
        }
    }

    return \%words;
}

1;
