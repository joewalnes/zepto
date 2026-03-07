#!/usr/bin/env perl
# Performance tests for Zepto::FindEngine
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time);
use lib 'lib';

use Zepto::FindEngine;
use Zepto::Document;

# =============================================================================
# Test Setup
# =============================================================================

sub create_doc_with_lines {
    my ($line_count, $content_fn) = @_;
    $content_fn //= sub { "foo bar baz line $_[0]\n" };

    my $doc = Zepto::Document->new();
    my $text = '';
    for my $i (1 .. $line_count) {
        $text .= $content_fn->($i);
    }
    $doc->insert(0, $text);
    return $doc;
}

sub measure_ms {
    my ($code, $iterations) = @_;
    $iterations //= 1;

    my @times;
    for (1 .. $iterations) {
        my $start = time();
        $code->();
        push @times, (time() - $start) * 1000;
    }

    @times = sort { $a <=> $b } @times;
    return {
        min    => $times[0],
        max    => $times[-1],
        median => $times[int(@times / 2)],
        p95    => $times[int(@times * 0.95)],
        mean   => (sum(@times) / @times),
    };
}

sub sum { my $t = 0; $t += $_ for @_; $t }

# =============================================================================
# Viewport Search Performance
# =============================================================================

subtest 'Viewport search - 50 lines should be <5ms' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    my $stats = measure_ms(sub {
        $engine->search('foo', 0, 50);
    }, 100);

    diag sprintf("Viewport search (50 lines): min=%.2fms median=%.2fms p95=%.2fms max=%.2fms",
        $stats->{min}, $stats->{median}, $stats->{p95}, $stats->{max});

    ok($stats->{median} < 5, "Median viewport search < 5ms (got $stats->{median}ms)");
    ok($stats->{p95} < 20, "P95 viewport search < 20ms (got $stats->{p95}ms)");
};

subtest 'Viewport search - single char (many matches)' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    my $stats = measure_ms(sub {
        $engine->search('a', 0, 50);  # 'a' appears multiple times per line
    }, 100);

    diag sprintf("Single char search (50 lines): min=%.2fms median=%.2fms p95=%.2fms",
        $stats->{min}, $stats->{median}, $stats->{p95});

    ok($stats->{median} < 5, "Single char median < 5ms (got $stats->{median}ms)");
};

subtest 'Viewport search - regex pattern' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    my $stats = measure_ms(sub {
        $engine->search('foo.*baz', 0, 50, use_regex => 1);
    }, 100);

    diag sprintf("Regex search (50 lines): min=%.2fms median=%.2fms p95=%.2fms",
        $stats->{min}, $stats->{median}, $stats->{p95});

    ok($stats->{median} < 10, "Regex median < 10ms (got $stats->{median}ms)");
};

# =============================================================================
# Background Search Performance
# =============================================================================

subtest 'Background search - full 10k lines' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    my $start = time();
    $engine->search('foo', 0, 50);

    my $ticks = 0;
    while ($engine->is_searching) {
        $engine->tick(10);  # 10ms chunks
        $ticks++;
    }
    my $elapsed = (time() - $start) * 1000;

    my $match_count = $engine->match_count;
    diag sprintf("Full search: %.2fms, %d ticks, %d matches", $elapsed, $ticks, $match_count);

    is($match_count, 10000, "Found all 10000 matches");
    ok($ticks > 1, "Search was chunked (not blocking)");
};

subtest 'Background search - tick respects time budget' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    $engine->search('foo', 0, 50);

    # Each tick should take ~10ms or less
    my @tick_times;
    while ($engine->is_searching) {
        my $start = time();
        $engine->tick(10);
        push @tick_times, (time() - $start) * 1000;
    }

    my $max_tick = (sort { $b <=> $a } @tick_times)[0];
    diag sprintf("Tick times: max=%.2fms, count=%d", $max_tick, scalar(@tick_times));

    # Allow some slack (20ms) for scheduling jitter
    ok($max_tick < 30, "Max tick time < 30ms (got ${max_tick}ms)");
};

# =============================================================================
# Abort Performance
# =============================================================================

subtest 'Abort is instant' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    # Start a search
    $engine->search('a', 0, 50);  # 'a' will have many matches
    $engine->tick(20);  # Let it run a bit

    # Now abort and start new search - should be instant
    my $start = time();
    my $matches = $engine->search('xyz', 0, 50);  # Different term
    my $elapsed = (time() - $start) * 1000;

    diag sprintf("Abort + new viewport search: %.2fms", $elapsed);

    ok($elapsed < 10, "Abort + new search < 10ms (got ${elapsed}ms)");
    is(scalar(@$matches), 0, "New search returned correct results (0 matches for 'xyz')");
};

subtest 'Rapid typing simulation' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    # Simulate typing "foobar" character by character
    my @terms = qw(f fo foo foob fooba foobar);
    my @search_times;

    for my $term (@terms) {
        my $start = time();
        $engine->search($term, 0, 50);
        push @search_times, (time() - $start) * 1000;

        # Simulate small delay between keypresses
        $engine->tick(5);  # Let background run a tiny bit
    }

    my $max_time = (sort { $b <=> $a } @search_times)[0];
    diag sprintf("Rapid typing - max search time: %.2fms", $max_time);

    ok($max_time < 50, "All viewport searches < 50ms (max was ${max_time}ms)");
};

# =============================================================================
# Large Document Performance
# =============================================================================

subtest 'Large document - 50k lines' => sub {
    plan skip_all => 'Set PERF_LARGE=1 to run large tests' unless $ENV{PERF_LARGE};

    my $doc = create_doc_with_lines(50000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    # Viewport should still be fast
    my $stats = measure_ms(sub {
        $engine->search('foo', 1000, 1050);  # Middle of doc
    }, 20);

    diag sprintf("50k doc viewport: median=%.2fms p95=%.2fms", $stats->{median}, $stats->{p95});
    ok($stats->{median} < 5, "Viewport still fast on large doc");
};

# =============================================================================
# Match Quality
# =============================================================================

subtest 'Match correctness' => sub {
    my $doc = Zepto::Document->new();
    $doc->insert(0, "hello world\nhello there\nworld hello\n");

    my $engine = Zepto::FindEngine->new(document => $doc);
    my $matches = $engine->search('hello', 0, 10);

    # Complete background search
    while ($engine->is_searching) {
        $engine->tick(100);
    }

    my $all = $engine->all_matches;
    is(scalar(@$all), 3, "Found 3 'hello' matches");

    # Check positions
    is($all->[0]{line}, 0, "First match on line 0");
    is($all->[0]{col}, 0, "First match at col 0");
    is($all->[1]{line}, 1, "Second match on line 1");
    is($all->[2]{line}, 2, "Third match on line 2");
    is($all->[2]{col}, 6, "Third match at col 6");
};

subtest 'Case insensitive search' => sub {
    my $doc = Zepto::Document->new();
    $doc->insert(0, "Hello HELLO hello\n");

    my $engine = Zepto::FindEngine->new(document => $doc);
    $engine->search('hello', 0, 10, case_sensitive => 0);

    while ($engine->is_searching) { $engine->tick(100); }

    is($engine->match_count, 3, "Case insensitive found all 3");
};

subtest 'Case sensitive search' => sub {
    my $doc = Zepto::Document->new();
    $doc->insert(0, "Hello HELLO hello\n");

    my $engine = Zepto::FindEngine->new(document => $doc);
    $engine->search('hello', 0, 10, case_sensitive => 1);

    while ($engine->is_searching) { $engine->tick(100); }

    is($engine->match_count, 1, "Case sensitive found only 1");
};

# =============================================================================
# Replace Preview Performance
# =============================================================================

subtest 'Replace preview - viewport only' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    # Search first
    $engine->search('foo', 0, 50);

    # Measure preview generation
    my $stats = measure_ms(sub {
        my $preview = $engine->preview_viewport('REPLACEMENT', 0, 50);
    }, 100);

    diag sprintf("Replace preview (50 lines): min=%.2fms median=%.2fms p95=%.2fms",
        $stats->{min}, $stats->{median}, $stats->{p95});

    ok($stats->{median} < 5, "Replace preview median < 5ms (got $stats->{median}ms)");
};

subtest 'Replace preview - rapid typing' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    $engine->search('foo', 0, 50);

    # Simulate typing replacement character by character
    my @replacements = ('X', 'XX', 'XXX', 'XXXX', 'XXXXX');
    my @times;

    for my $rep (@replacements) {
        my $start = time();
        my $preview = $engine->preview_viewport($rep, 0, 50);
        push @times, (time() - $start) * 1000;
    }

    my $max_time = (sort { $b <=> $a } @times)[0];
    diag sprintf("Rapid replace typing - max preview time: %.2fms", $max_time);

    ok($max_time < 50, "All previews < 50ms (max was ${max_time}ms)");
};

subtest 'Replace preview correctness' => sub {
    my $doc = Zepto::Document->new();
    $doc->insert(0, "foo bar foo baz\n");

    my $engine = Zepto::FindEngine->new(document => $doc);
    $engine->search('foo', 0, 10);

    my $preview = $engine->preview_line(0, 'XXX');

    is($preview->{text}, 'XXX bar XXX baz', 'Replaced text is correct');
    is(scalar(@{$preview->{highlights}}), 2, 'Two highlights');
    is($preview->{highlights}[0]{start}, 0, 'First highlight at 0');
    is($preview->{highlights}[0]{end}, 3, 'First highlight ends at 3');
    is($preview->{highlights}[1]{start}, 8, 'Second highlight at 8');
};

subtest 'Full workflow - search then replace typing' => sub {
    my $doc = create_doc_with_lines(10000);
    my $engine = Zepto::FindEngine->new(document => $doc);

    # Simulate: type "foo" in find box
    my @search_times;
    for my $term ('f', 'fo', 'foo') {
        my $start = time();
        $engine->search($term, 0, 50);
        push @search_times, (time() - $start) * 1000;
    }

    # Simulate: type "bar" in replace box
    my @preview_times;
    for my $rep ('b', 'ba', 'bar') {
        my $start = time();
        $engine->preview_viewport($rep, 0, 50);
        push @preview_times, (time() - $start) * 1000;
    }

    my $max_search = (sort { $b <=> $a } @search_times)[0];
    my $max_preview = (sort { $b <=> $a } @preview_times)[0];

    diag sprintf("Full workflow - max search: %.2fms, max preview: %.2fms",
        $max_search, $max_preview);

    ok($max_search < 10, "Search always < 10ms");
    ok($max_preview < 10, "Preview always < 10ms");
};

done_testing();
