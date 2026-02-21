#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';

use Zepto::LineMap;

# Helper: build a LineMap from hunks array and doc line count
sub make_linemap {
    my ($doc_line_count, $hunks) = @_;
    return Zepto::LineMap->new(
        doc_line_count => $doc_line_count,
        hunks          => $hunks,
    );
}

# =============================================================================
# No expansions — display rows equal doc lines
# =============================================================================

subtest 'No expansions: identity mapping' => sub {
    my $lm = make_linemap(5, []);

    is($lm->total_display_rows(), 5, 'Total rows equals doc lines');
    for my $i (0..4) {
        my $entry = $lm->display_entry($i);
        is($entry->{type}, 'doc', "Row $i is doc type");
        is($entry->{line}, $i, "Row $i maps to doc line $i");
    }
    is($lm->doc_line_to_display(0), 0, 'Doc line 0 at display 0');
    is($lm->doc_line_to_display(4), 4, 'Doc line 4 at display 4');
    is($lm->extra_rows_before(0), 0, 'No extra rows before line 0');
    is($lm->extra_rows_before(4), 0, 'No extra rows before line 4');
};

# =============================================================================
# Expanded modified hunk
# =============================================================================

subtest 'Expanded modified hunk' => sub {
    # Doc has 5 lines. Hunk: base lines [1,2] replaced current lines [2,3]
    # (base had 2 lines at positions 1-2, current has 2 lines at positions 2-3)
    my @hunks = ({
        type           => 'modified',
        base_lines     => [1, 2],
        current_lines  => [2, 3],
        prev_curr_line => 1,
        next_curr_line => 4,
    });
    my $lm = make_linemap(5, \@hunks);
    $lm->toggle_hunk(0);

    # Expected display:
    # 0: doc 0
    # 1: doc 1
    # 2: old base_line 1  (expanded old)
    # 3: old base_line 2  (expanded old)
    # 4: doc 2 (green, hunk_idx=0)
    # 5: doc 3 (green, hunk_idx=0)
    # 6: doc 4
    is($lm->total_display_rows(), 7, 'Total rows = 5 doc + 2 old');

    my $e0 = $lm->display_entry(0);
    is($e0->{type}, 'doc', 'Row 0 is doc');
    is($e0->{line}, 0, 'Row 0 = doc line 0');

    my $e1 = $lm->display_entry(1);
    is($e1->{type}, 'doc', 'Row 1 is doc');
    is($e1->{line}, 1, 'Row 1 = doc line 1');

    my $e2 = $lm->display_entry(2);
    is($e2->{type}, 'old', 'Row 2 is old');
    is($e2->{base_line}, 1, 'Row 2 = base line 1');
    is($e2->{hunk_idx}, 0, 'Row 2 belongs to hunk 0');

    my $e3 = $lm->display_entry(3);
    is($e3->{type}, 'old', 'Row 3 is old');
    is($e3->{base_line}, 2, 'Row 3 = base line 2');

    my $e4 = $lm->display_entry(4);
    is($e4->{type}, 'doc', 'Row 4 is doc');
    is($e4->{line}, 2, 'Row 4 = doc line 2');
    is($e4->{hunk_idx}, 0, 'Row 4 tagged with hunk_idx 0 (green)');

    my $e5 = $lm->display_entry(5);
    is($e5->{type}, 'doc', 'Row 5 is doc');
    is($e5->{line}, 3, 'Row 5 = doc line 3');
    is($e5->{hunk_idx}, 0, 'Row 5 tagged with hunk_idx 0 (green)');

    my $e6 = $lm->display_entry(6);
    is($e6->{type}, 'doc', 'Row 6 is doc');
    is($e6->{line}, 4, 'Row 6 = doc line 4');
    ok(!defined $e6->{hunk_idx}, 'Row 6 not tagged with hunk');

    # Coordinate mapping
    is($lm->doc_line_to_display(0), 0, 'Doc 0 at display 0');
    is($lm->doc_line_to_display(1), 1, 'Doc 1 at display 1');
    is($lm->doc_line_to_display(2), 4, 'Doc 2 at display 4 (after old lines)');
    is($lm->doc_line_to_display(4), 6, 'Doc 4 at display 6');

    is($lm->extra_rows_before(2), 2, '2 extra rows before doc line 2');
    is($lm->extra_rows_before(4), 2, '2 extra rows before doc line 4');
    is($lm->extra_rows_before(0), 0, '0 extra rows before doc line 0');
};

# =============================================================================
# Expanded deleted hunk
# =============================================================================

subtest 'Expanded deleted hunk' => sub {
    # Doc has 3 lines. Deletion hunk after doc line 1 (base lines [2,3] deleted)
    my @hunks = ({
        type           => 'deleted',
        base_lines     => [2, 3],
        current_lines  => [],
        prev_curr_line => 1,
        next_curr_line => 2,
    });
    my $lm = make_linemap(3, \@hunks);
    $lm->toggle_hunk(0);

    # Expected:
    # 0: doc 0
    # 1: doc 1
    # 2: old base_line 2
    # 3: old base_line 3
    # 4: doc 2
    is($lm->total_display_rows(), 5, 'Total rows = 3 doc + 2 old');

    my $e2 = $lm->display_entry(2);
    is($e2->{type}, 'old', 'Row 2 is old');
    is($e2->{base_line}, 2, 'Row 2 = base line 2');

    my $e4 = $lm->display_entry(4);
    is($e4->{type}, 'doc', 'Row 4 is doc');
    is($e4->{line}, 2, 'Row 4 = doc line 2');

    is($lm->doc_line_to_display(2), 4, 'Doc 2 at display 4');
    is($lm->extra_rows_before(2), 2, '2 extra rows before doc line 2');
};

# =============================================================================
# Expanded added hunk (no old lines)
# =============================================================================

subtest 'Expanded added hunk' => sub {
    # Doc has 4 lines. Addition hunk: current lines [1,2] are new
    my @hunks = ({
        type           => 'added',
        base_lines     => [],
        current_lines  => [1, 2],
        prev_curr_line => 0,
        next_curr_line => 3,
    });
    my $lm = make_linemap(4, \@hunks);
    $lm->toggle_hunk(0);

    # No old lines to insert, but current lines get green highlight
    # 0: doc 0
    # 1: doc 1 (green, hunk_idx=0)
    # 2: doc 2 (green, hunk_idx=0)
    # 3: doc 3
    is($lm->total_display_rows(), 4, 'Total rows unchanged (no old lines for additions)');

    my $e1 = $lm->display_entry(1);
    is($e1->{type}, 'doc', 'Row 1 is doc');
    is($e1->{hunk_idx}, 0, 'Row 1 tagged with hunk 0 (green)');

    my $e3 = $lm->display_entry(3);
    ok(!defined $e3->{hunk_idx}, 'Row 3 not tagged');
};

# =============================================================================
# Toggle collapse
# =============================================================================

subtest 'Toggle collapse restores identity' => sub {
    my @hunks = ({
        type           => 'modified',
        base_lines     => [1],
        current_lines  => [1],
        prev_curr_line => 0,
        next_curr_line => 2,
    });
    my $lm = make_linemap(3, \@hunks);

    is($lm->total_display_rows(), 3, 'Before expand: 3 rows');

    $lm->toggle_hunk(0);
    is($lm->total_display_rows(), 4, 'After expand: 4 rows (1 old added)');

    $lm->toggle_hunk(0);
    is($lm->total_display_rows(), 3, 'After collapse: back to 3 rows');

    my $e1 = $lm->display_entry(1);
    is($e1->{type}, 'doc', 'Row 1 is doc again');
    ok(!defined $e1->{hunk_idx}, 'Row 1 not tagged after collapse');
};

# =============================================================================
# Multiple expanded hunks
# =============================================================================

subtest 'Multiple expanded hunks' => sub {
    # Doc has 7 lines. Two hunks:
    # Hunk 0: modified, base [1], current [1], between doc 0 and 2
    # Hunk 1: deleted, base [4,5], current [], between doc 4 and 5
    my @hunks = (
        {
            type           => 'modified',
            base_lines     => [1],
            current_lines  => [1],
            prev_curr_line => 0,
            next_curr_line => 2,
        },
        {
            type           => 'deleted',
            base_lines     => [4, 5],
            current_lines  => [],
            prev_curr_line => 4,
            next_curr_line => 5,
        },
    );
    my $lm = make_linemap(7, \@hunks);
    $lm->toggle_hunk(0);
    $lm->toggle_hunk(1);

    # Expected:
    # 0: doc 0
    # 1: old base 1      (hunk 0)
    # 2: doc 1 (green)    (hunk 0)
    # 3: doc 2
    # 4: doc 3
    # 5: doc 4
    # 6: old base 4      (hunk 1)
    # 7: old base 5      (hunk 1)
    # 8: doc 5
    # 9: doc 6
    is($lm->total_display_rows(), 10, 'Total rows = 7 doc + 1 old (hunk0) + 2 old (hunk1)');

    is($lm->doc_line_to_display(0), 0, 'Doc 0 at display 0');
    is($lm->doc_line_to_display(1), 2, 'Doc 1 at display 2');
    is($lm->doc_line_to_display(5), 8, 'Doc 5 at display 8');
    is($lm->doc_line_to_display(6), 9, 'Doc 6 at display 9');

    is($lm->extra_rows_before(1), 1, '1 extra row before doc 1');
    is($lm->extra_rows_before(5), 3, '3 extra rows before doc 5');
};

# =============================================================================
# visible_entries
# =============================================================================

subtest 'visible_entries returns correct slice' => sub {
    my @hunks = ({
        type           => 'modified',
        base_lines     => [1],
        current_lines  => [1],
        prev_curr_line => 0,
        next_curr_line => 2,
    });
    my $lm = make_linemap(5, \@hunks);
    $lm->toggle_hunk(0);

    # Display: doc0, old1, doc1(green), doc2, doc3, doc4
    # Viewport starting at scroll_line=0, height=3
    my $entries = $lm->visible_entries(0, 3);
    is(scalar @$entries, 3, 'Returns 3 entries');
    is($entries->[0]{type}, 'doc', 'First visible is doc');
    is($entries->[1]{type}, 'old', 'Second visible is old');
    is($entries->[2]{type}, 'doc', 'Third visible is doc');

    # Viewport starting at scroll_line=2 (doc line 2), height=3
    $entries = $lm->visible_entries(2, 3);
    is(scalar @$entries, 3, 'Returns 3 entries from scroll_line=2');
    is($entries->[0]{type}, 'doc', 'First is doc line 2');
    is($entries->[0]{line}, 2, 'Correct doc line');
};

# =============================================================================
# Deletion at start of file
# =============================================================================

subtest 'Deletion at start of file' => sub {
    my @hunks = ({
        type           => 'deleted',
        base_lines     => [0, 1],
        current_lines  => [],
        prev_curr_line => -1,
        next_curr_line => 0,
    });
    my $lm = make_linemap(3, \@hunks);
    $lm->toggle_hunk(0);

    # Expected:
    # 0: old base 0
    # 1: old base 1
    # 2: doc 0
    # 3: doc 1
    # 4: doc 2
    is($lm->total_display_rows(), 5, 'Total rows = 3 + 2 old');

    my $e0 = $lm->display_entry(0);
    is($e0->{type}, 'old', 'Row 0 is old');
    is($e0->{base_line}, 0, 'Row 0 = base line 0');

    is($lm->doc_line_to_display(0), 2, 'Doc 0 at display 2');
};

# =============================================================================
# collapse_all
# =============================================================================

subtest 'collapse_all resets all expansions' => sub {
    my @hunks = (
        { type => 'modified', base_lines => [0], current_lines => [0], prev_curr_line => -1, next_curr_line => 1 },
        { type => 'added', base_lines => [], current_lines => [2], prev_curr_line => 1, next_curr_line => 3 },
    );
    my $lm = make_linemap(4, \@hunks);
    $lm->toggle_hunk(0);
    $lm->toggle_hunk(1);

    ok($lm->is_expanded(0), 'Hunk 0 expanded');
    ok($lm->is_expanded(1), 'Hunk 1 expanded');

    $lm->collapse_all();
    ok(!$lm->is_expanded(0), 'Hunk 0 collapsed');
    ok(!$lm->is_expanded(1), 'Hunk 1 collapsed');
    is($lm->total_display_rows(), 4, 'Back to identity mapping');
};

done_testing();
