#!/usr/bin/env perl
# Correctness + performance regression test for Minimap's VCS-status row
# aggregation (QA-REG-233).
#
# Background: _aggregate_vcs_status() scanned every document line in a
# minimap row's span, with no cap — unlike the braille-density path
# (_get_cached_rows), which already subsamples via MAX_SAMPLE_LINES. Because
# the minimap's cache key includes content_version() (bumped on every edit),
# this full per-line VCS scan re-ran on every keystroke, not just when VCS
# state actually changed. On a large file this meant tens to hundreds of
# thousands of hash lookups per keystroke.
#
# The fix adds MAX_VCS_SAMPLE_LINES (200): when a row's line span exceeds
# it, sample evenly spaced lines instead of scanning every one — same
# technique as the braille cap, just a larger sample count (VCS status is a
# correctness signal, not a fixed-resolution rendering grid; see the comment
# on MAX_VCS_SAMPLE_LINES in Minimap.pm for the full reasoning).
#
# This test reconstructs the OLD algorithm verbatim (as it existed in
# Minimap.pm before the fix) as a local sub, so it can assert correctness
# (old vs. new agree below the cap, and new still catches any changed hunk
# that spans a full sample gap) and performance (old is demonstrably slow at
# a workload size the new code handles instantly) in the same run, without
# needing to check out a prior git revision. It also demonstrates — not just
# asserts away — the one accepted accuracy tradeoff: an isolated single-line
# change that doesn't land on a sampled line, in a row spanning more than
# MAX_VCS_SAMPLE_LINES lines, can be missed by the new code where the old
# code would have caught it.
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time);
use File::Temp qw(tempfile);

use lib 'lib';
use Zepto::Minimap;
use Zepto::Document;

# =============================================================================
# OLD algorithm, reconstructed verbatim from pre-fix Minimap.pm for
# side-by-side comparison. DO NOT "clean this up" to match the new code —
# the whole point is that it's an independent, unmodified reference.
# =============================================================================

sub old_aggregate_vcs_status {
    my ($doc, $start_line, $end_line) = @_;

    return undef unless $doc && $doc->can('vcs_change_status');

    my $has_added = 0;
    my $has_modified = 0;
    my $has_deleted = 0;

    my $line_count = $doc->line_count();

    for my $line ($start_line .. $end_line - 1) {
        last if $line >= $line_count;

        my $change = $doc->vcs_change_status($line);
        if ($change) {
            if ($change eq 'added') {
                $has_added = 1;
            } else {
                $has_modified = 1;
            }
        }

        my $del = $doc->vcs_deletion_status($line);
        $has_deleted = 1 if $del;

        last if $has_deleted;
    }

    return 'deleted'  if $has_deleted;
    return 'modified' if $has_modified;
    return 'added'    if $has_added;
    return undef;
}

# Mirrors the sampling formula in Minimap.pm's _aggregate_vcs_status exactly,
# so tests can compute which lines are guaranteed to be sampled (and which
# are guaranteed NOT to be) rather than relying on luck.
sub sample_lines_for {
    my ($start_line, $end_line, $cap) = @_;
    my $line_span = $end_line - $start_line;
    return ($start_line .. $end_line - 1) if $line_span <= $cap;
    my @sample;
    for my $i (0 .. $cap - 1) {
        push @sample, $start_line + int($i * ($line_span - 1) / ($cap - 1));
    }
    return @sample;
}

# =============================================================================
# Fixtures
# =============================================================================

# A minimal fake Document exposing exactly the duck-typed interface
# _aggregate_vcs_status() actually uses (can/line_count/vcs_change_status/
# vcs_deletion_status). Avoids real file I/O so performance timings measure
# only the aggregation logic, and correctness fixtures can be built directly
# from line-number sets.
package FakeVcsDoc;
sub new {
    my ($class, %args) = @_;
    return bless {
        line_count => $args{line_count},
        added      => $args{added} || {},
        modified   => $args{modified} || {},
        deleted    => $args{deleted} || {},
    }, $class;
}
sub line_count { $_[0]->{line_count} }
sub vcs_change_status {
    my ($self, $line) = @_;
    return 'added'    if $self->{added}{$line};
    return 'modified' if $self->{modified}{$line};
    return undef;
}
sub vcs_deletion_status {
    my ($self, $line) = @_;
    return $self->{deleted}{$line};
}
package main;

my $CAP = Zepto::Minimap::MAX_VCS_SAMPLE_LINES();

sub create_temp_file {
    my ($content) = @_;
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    binmode($fh, ':utf8');
    print $fh $content;
    close $fh;
    return $filename;
}

# =============================================================================
# Correctness: below the cap, old and new are byte-identical (no accuracy
# loss at all — every line is still checked, same as before the fix).
# =============================================================================

subtest 'Below cap: old and new agree — no VCS data' => sub {
    my $doc = FakeVcsDoc->new(line_count => 50);
    is(Zepto::Minimap::_aggregate_vcs_status($doc, 0, 50),
       old_aggregate_vcs_status($doc, 0, 50),
       'both return undef with no changes');
};

subtest 'Below cap: old and new agree — scattered added/modified/deleted' => sub {
    my %added    = map { $_ => 1 } (2, 15, 40);
    my %modified = map { $_ => 1 } (5, 20);
    my %deleted  = (30 => 'above');
    my $doc = FakeVcsDoc->new(line_count => 50, added => \%added, modified => \%modified, deleted => \%deleted);

    is(Zepto::Minimap::_aggregate_vcs_status($doc, 0, 50),
       old_aggregate_vcs_status($doc, 0, 50),
       'deleted (highest priority) — old and new agree');

    is(Zepto::Minimap::_aggregate_vcs_status($doc, 0, 10),
       old_aggregate_vcs_status($doc, 0, 10),
       'added only in range — old and new agree');

    is(Zepto::Minimap::_aggregate_vcs_status($doc, 3, 25),
       old_aggregate_vcs_status($doc, 3, 25),
       'modified in range — old and new agree');

    is(Zepto::Minimap::_aggregate_vcs_status($doc, 0, 50), 'deleted', 'sanity: actually detects deleted, not a vacuous undef==undef match');
};

subtest 'Below cap: single-line isolated change is always caught (span == 1)' => sub {
    my %added = (7 => 1);
    my $doc = FakeVcsDoc->new(line_count => 20, added => \%added);
    is(Zepto::Minimap::_aggregate_vcs_status($doc, 7, 8), 'added', 'exact single-line row still detects its own change');
};

# =============================================================================
# Correctness above the cap: the guaranteed-catch property.
# =============================================================================

subtest 'Above cap: change exactly on a sampled line is always caught' => sub {
    my $span = 3000;    # > CAP, forces subsampling
    my @samples = sample_lines_for(0, $span, $CAP);
    my $target = $samples[int(@samples / 2)];    # a middle sample point

    my %added = ($target => 1);
    my $doc = FakeVcsDoc->new(line_count => $span, added => \%added);

    is(Zepto::Minimap::_aggregate_vcs_status($doc, 0, $span), 'added',
       "change on sampled line $target (of " . scalar(@samples) . " samples) is detected");
    is(old_aggregate_vcs_status($doc, 0, $span), 'added', 'sanity: old algorithm also detects it (same ground truth)');
};

subtest 'Above cap: a hunk spanning a full sample gap is always caught' => sub {
    my $span = 3000;
    my @samples = sort { $a <=> $b } sample_lines_for(0, $span, $CAP);

    # Find the widest gap between consecutive samples, and fill every line
    # in it with a change. By construction this hunk cannot avoid containing
    # at least one sample point.
    my ($gap_start, $gap_end, $widest) = (0, 0, 0);
    for my $i (0 .. $#samples - 1) {
        my $gap = $samples[$i + 1] - $samples[$i];
        if ($gap > $widest) {
            $widest = $gap;
            $gap_start = $samples[$i];
            $gap_end = $samples[$i + 1];
        }
    }
    ok($widest > 0, "found a real sample gap (widest=$widest) to fill");

    my %modified = map { $_ => 1 } ($gap_start .. $gap_end);
    my $doc = FakeVcsDoc->new(line_count => $span, modified => \%modified);

    is(Zepto::Minimap::_aggregate_vcs_status($doc, 0, $span), 'modified',
       "contiguous hunk filling the widest sample gap ($gap_start..$gap_end) is detected");
};

# =============================================================================
# Honesty: the accepted accuracy tradeoff, demonstrated, not just described.
# An isolated single-line change strictly between two sample points, in a
# span above the cap, is missed by the new code (unlike the old code).
# =============================================================================

subtest 'Above cap: KNOWN LIMITATION — isolated single-line change off the sample grid can be missed' => sub {
    my $span = 3000;
    my @samples = sort { $a <=> $b } sample_lines_for(0, $span, $CAP);

    # Find a gap of at least 3 lines so there's a line strictly inside it
    # (not equal to either endpoint sample).
    my $victim;
    for my $i (0 .. $#samples - 1) {
        if ($samples[$i + 1] - $samples[$i] >= 3) {
            $victim = $samples[$i] + 1;    # strictly between two samples
            last;
        }
    }
    ok(defined $victim, 'found a gap wide enough to place an unsampled line') or return;

    my %added = ($victim => 1);
    my $doc = FakeVcsDoc->new(line_count => $span, added => \%added);

    is(old_aggregate_vcs_status($doc, 0, $span), 'added',
       'old (unbounded scan) algorithm catches the isolated change, as expected');
    is(Zepto::Minimap::_aggregate_vcs_status($doc, 0, $span), undef,
       'new (sampled) algorithm misses it — this is the accepted, documented tradeoff of subsampling above the cap, ' .
       'the same class of tradeoff the pre-existing braille MAX_SAMPLE_LINES cap already accepts for text density');
};

# =============================================================================
# Correctness at the public API level (Minimap->compute), not just the
# private helper — a known change at a specific line shows up in the
# corresponding minimap row, at the sampled resolution.
# =============================================================================

subtest 'Public API: known change at a specific line reflects in its minimap row (below cap)' => sub {
    my $content = join('', map { "line $_\n" } 1 .. 40);
    my $filename = create_temp_file($content);
    my $doc = Zepto::Document->load($filename);
    $doc->{_vcs_diff} = { added => [10], modified => [], deleted => [] };
    $doc->{_vcs_last_diff} = time();
    $doc->_rebuild_vcs_lookup();

    Zepto::Minimap->invalidate_cache();
    my $result = Zepto::Minimap->compute(document => $doc, height => 40);

    is($result->{rows}[10]{vcs}, 'added', "row 10 (1:1 mapping) reflects the injected 'added' change");
    for my $i (0 .. 39) {
        next if $i == 10;
        is($result->{rows}[$i]{vcs}, undef, "row $i has no VCS status (no change there)") if $i < 5 || $i > 15;
    }
};

# =============================================================================
# Performance: new algorithm is dramatically faster, and comfortably under a
# bound the old algorithm demonstrably violates, at more than one scale.
# =============================================================================

sub build_scattered_added {
    my ($span) = @_;
    my %added;
    for (my $l = 0; $l < $span; $l += 97) { $added{$l} = 1; }
    return \%added;
}

for my $scale ([20000, 2], [100000, 5]) {
    my ($span, $new_bound_ms) = @$scale;

    subtest "Performance at line span=$span" => sub {
        my $added = build_scattered_added($span);
        my $doc = FakeVcsDoc->new(line_count => $span, added => $added);

        # Warm up Perl's method resolution cache so both measurements reflect
        # steady-state cost, not first-call warmup.
        old_aggregate_vcs_status($doc, 0, 1);
        Zepto::Minimap::_aggregate_vcs_status($doc, 0, 1);

        my $t0 = time();
        my $old_status = old_aggregate_vcs_status($doc, 0, $span);
        my $old_ms = (time() - $t0) * 1000;

        my $t1 = time();
        my $new_status = Zepto::Minimap::_aggregate_vcs_status($doc, 0, $span);
        my $new_ms = (time() - $t1) * 1000;

        diag sprintf("span=%d: old=%.3fms new=%.3fms (%.1fx faster)",
            $span, $old_ms, $new_ms, $new_ms > 0 ? $old_ms / $new_ms : 0);

        is($old_status, 'added', 'sanity: old algorithm actually found the scattered changes');
        is($new_status, 'added', 'sanity: new algorithm also found them (dense scatter, well within sample density)');

        # Sanity: prove this workload actually discriminates — the old
        # algorithm must exceed the bound we're about to hold the new one
        # to, otherwise the bound below would be a vacuous gate.
        ok($old_ms > $new_bound_ms,
            "old (unfixed) algorithm exceeds ${new_bound_ms}ms bound (took ${old_ms}ms) — workload is discriminating");

        ok($new_ms < $new_bound_ms,
            "new (fixed) algorithm comfortably meets ${new_bound_ms}ms bound (took ${new_ms}ms)");

        ok($new_ms * 5 < $old_ms,
            "new algorithm is at least 5x faster than old at this scale (old=${old_ms}ms new=${new_ms}ms)");
    };
}

# Recompute-on-every-keystroke behavior: full Minimap->compute() through the
# real cache path, on a large real Document, simulating several edits.
subtest 'Full compute() stays fast across repeated simulated edits on a large document' => sub {
    my $num_lines = 30000;
    my $content = join('', map { "line $_ content here\n" } 1 .. $num_lines);
    my $filename = create_temp_file($content);
    my $doc = Zepto::Document->load($filename);
    my $added = build_scattered_added($num_lines);
    $doc->{_vcs_diff} = { added => [keys %$added], modified => [], deleted => [] };
    $doc->{_vcs_last_diff} = time();
    $doc->_rebuild_vcs_lookup();

    require Zepto::View;
    my $view = Zepto::View->new(document => $doc);
    Zepto::Minimap->invalidate_cache();
    Zepto::Minimap->compute(document => $doc, view => $view, height => 40);   # warm up

    my $n_edits = 5;
    my $t0 = time();
    for (1 .. $n_edits) {
        $doc->{_content_version}++;    # simulate what an edit does to the cache key
        Zepto::Minimap->compute(document => $doc, view => $view, height => 40);
    }
    my $total_ms = (time() - $t0) * 1000;
    diag sprintf("%d lines, %d simulated keystrokes: %.2fms total, %.2fms/keystroke",
        $num_lines, $n_edits, $total_ms, $total_ms / $n_edits);

    ok($total_ms < 200, "$n_edits recomputes on a $num_lines-line document complete in under 200ms (took ${total_ms}ms)");
};

done_testing();
