#!/usr/bin/env perl
# =============================================================================
# Diff Constraint Tests
# =============================================================================
#
# Validates the key constraint: a deleted marker should NEVER appear directly
# adjacent (at line N-1 or N) to a modified or added marker.
#
# This constraint enables single-column gutter rendering without overlap.
# =============================================================================

use strict;
use warnings;
use Test::More;
use File::Basename;
use File::Spec;

my $test_dir = dirname(__FILE__);
my $lib_dir = File::Spec->catdir($test_dir, '..', 'lib');
unshift @INC, $lib_dir;

require Zepto::Diff;

# =============================================================================
# Helper: Check the adjacency constraint
# =============================================================================
# Returns 1 if constraint satisfied, 0 if violated
# Also returns explanation of violation

sub check_constraint {
    my ($result) = @_;

    my %added = map { $_ => 1 } @{$result->{added}};
    my %modified = map { $_ => 1 } @{$result->{modified}};
    my @deleted = @{$result->{deleted}};

    for my $del_line (@deleted) {
        # Deleted marker at line N means deletion occurred AFTER line N
        # The marker spans from line N to N+1 visually
        # So it conflicts if N or N+1 has an added/modified marker

        if ($added{$del_line} || $modified{$del_line}) {
            return (0, "Deleted marker at line $del_line conflicts with add/modify at same line");
        }
        if ($added{$del_line + 1} || $modified{$del_line + 1}) {
            return (0, "Deleted marker at line $del_line conflicts with add/modify at line " . ($del_line + 1));
        }
    }

    return (1, "OK");
}

# =============================================================================
# Helper: Run diff and check constraint
# =============================================================================

sub diff_and_check {
    my ($name, $base, $current, $expected) = @_;

    subtest $name => sub {
        my $result = Zepto::Diff->diff($base, $current);

        # Check constraint
        my ($ok, $msg) = check_constraint($result);
        ok($ok, "Adjacency constraint satisfied: $msg");

        # If expected results provided, verify them
        if ($expected) {
            is_deeply([sort { $a <=> $b } @{$result->{added}}],
                      [sort { $a <=> $b } @{$expected->{added} // []}],
                      "Added lines match") if exists $expected->{added};
            is_deeply([sort { $a <=> $b } @{$result->{modified}}],
                      [sort { $a <=> $b } @{$expected->{modified} // []}],
                      "Modified lines match") if exists $expected->{modified};
            is_deeply([sort { $a <=> $b } @{$result->{deleted}}],
                      [sort { $a <=> $b } @{$expected->{deleted} // []}],
                      "Deleted lines match") if exists $expected->{deleted};
        }

        # Debug output (only when VERBOSE is set)
        if ($ENV{VERBOSE}) {
            diag("Added: [@{$result->{added}}]");
            diag("Modified: [@{$result->{modified}}]");
            diag("Deleted: [@{$result->{deleted}}]");
        }
    };
}

# =============================================================================
# Test Cases
# =============================================================================

# --- Basic Operations ---

diff_and_check(
    "Single line addition at end",
    "line1\nline2",
    "line1\nline2\nline3",
    { added => [2], modified => [], deleted => [] }
);

diff_and_check(
    "Single line addition at start",
    "line1\nline2",
    "new\nline1\nline2",
    { added => [0], modified => [], deleted => [] }
);

diff_and_check(
    "Single line addition in middle",
    "line1\nline3",
    "line1\nline2\nline3",
    { added => [1], modified => [], deleted => [] }
);

diff_and_check(
    "Single line deletion at end",
    "line1\nline2\nline3",
    "line1\nline2",
    { added => [], modified => [], deleted => [1] }  # Deletion after line 1
);

diff_and_check(
    "Single line deletion at start",
    "line1\nline2\nline3",
    "line2\nline3",
    { added => [], modified => [], deleted => [0] }  # Deletion at/before line 0
);

diff_and_check(
    "Single line deletion in middle",
    "line1\nline2\nline3",
    "line1\nline3",
    { added => [], modified => [], deleted => [0] }  # Deletion after line 0
);

# --- Modifications (delete + add at same position) ---

diff_and_check(
    "Single line modification",
    "old line",
    "new line",
    { added => [], modified => [0], deleted => [] }
);

diff_and_check(
    "Single line modification at start",
    "old\nline2\nline3",
    "new\nline2\nline3",
    { added => [], modified => [0], deleted => [] }
);

diff_and_check(
    "Single line modification at end",
    "line1\nline2\nold",
    "line1\nline2\nnew",
    { added => [], modified => [2], deleted => [] }
);

diff_and_check(
    "Single line modification in middle",
    "line1\nold\nline3",
    "line1\nnew\nline3",
    { added => [], modified => [1], deleted => [] }
);

# --- Multi-line operations ---

diff_and_check(
    "Multiple line addition",
    "line1\nline5",
    "line1\nline2\nline3\nline4\nline5",
    { added => [1, 2, 3], modified => [], deleted => [] }
);

diff_and_check(
    "Multiple line deletion",
    "line1\nline2\nline3\nline4\nline5",
    "line1\nline5",
    { added => [], modified => [], deleted => [0] }  # Single marker for multiple deletes
);

diff_and_check(
    "Multiple line modification (same count)",
    "old1\nold2\nold3",
    "new1\nnew2\nnew3",
    { added => [], modified => [0, 1, 2], deleted => [] }
);

diff_and_check(
    "Replace 3 lines with 2 lines",
    "line1\nold1\nold2\nold3\nline5",
    "line1\nnew1\nnew2\nline5",
    { added => [], modified => [1, 2], deleted => [] }  # NO separate delete marker
);

diff_and_check(
    "Replace 2 lines with 3 lines",
    "line1\nold1\nold2\nline4",
    "line1\nnew1\nnew2\nnew3\nline4",
    { added => [], modified => [1, 2, 3], deleted => [] }  # All modifications
);

diff_and_check(
    "Replace 1 line with 5 lines",
    "before\nold\nafter",
    "before\nnew1\nnew2\nnew3\nnew4\nnew5\nafter",
    { added => [], modified => [1, 2, 3, 4, 5], deleted => [] }
);

diff_and_check(
    "Replace 5 lines with 1 line",
    "before\nold1\nold2\nold3\nold4\nold5\nafter",
    "before\nnew\nafter",
    { added => [], modified => [1], deleted => [] }  # NO separate delete marker
);

# --- Separate non-adjacent changes ---

diff_and_check(
    "Add at start, add at end",
    "middle",
    "start\nmiddle\nend",
    { added => [0, 2], modified => [], deleted => [] }
);

diff_and_check(
    "Delete at start, delete at end (non-adjacent)",
    "first\na\nb\nc\nlast",
    "a\nb\nc",
    { added => [], modified => [], deleted => [0, 2] }  # Separate deletions OK if not adjacent
);

diff_and_check(
    "Modify at start, modify at end (non-adjacent)",
    "old1\na\nb\nc\nold2",
    "new1\na\nb\nc\nnew2",
    { added => [], modified => [0, 4], deleted => [] }
);

# --- Complex scenarios that previously caused adjacent delete+add ---

diff_and_check(
    "Complete file rewrite",
    "old content\nmore old\nstuff",
    "completely\nnew\nfile",
    { added => [], modified => [0, 1, 2], deleted => [] }
);

diff_and_check(
    "Replace then delete at end",
    "keep\nold\nremove",
    "keep\nnew",
    { added => [], modified => [1], deleted => [] }  # Delete folded into modify
);

diff_and_check(
    "Delete then replace at end",
    "keep\nremove\nold",
    "keep\nnew",
    { added => [], modified => [1], deleted => [] }  # All one hunk
);

diff_and_check(
    "Add then delete (non-adjacent OK)",
    "a\nb\nc\nd",
    "a\nnew\nb\nd",
    { added => [1], modified => [], deleted => [2] }  # Should be non-adjacent
);

# --- Edge cases ---

diff_and_check(
    "Empty to content",
    "",
    "line1\nline2",
    { added => [0, 1], modified => [], deleted => [] }
);

diff_and_check(
    "Content to empty",
    "line1\nline2",
    "",
    { added => [], modified => [], deleted => [0] }
);

diff_and_check(
    "No change",
    "same\ncontent",
    "same\ncontent",
    { added => [], modified => [], deleted => [] }
);

diff_and_check(
    "Single empty line to content",
    "",
    "content",
    { added => [0], modified => [], deleted => [] }
);

diff_and_check(
    "Content to single empty line",
    "content",
    "",
    { added => [], modified => [], deleted => [0] }
);

# --- Stress test: many changes ---

diff_and_check(
    "Alternating changes",
    "a\nb\nc\nd\ne\nf",
    "A\nb\nC\nd\nE\nf",
    { added => [], modified => [0, 2, 4], deleted => [] }
);

diff_and_check(
    "Every line modified",
    "1\n2\n3\n4\n5",
    "a\nb\nc\nd\ne",
    { added => [], modified => [0, 1, 2, 3, 4], deleted => [] }
);

# --- The critical case: what broke before ---

diff_and_check(
    "Delete 2 lines, add 1 line at same position",
    "before\ndelete1\ndelete2\nafter",
    "before\nadd1\nafter",
    { added => [], modified => [1], deleted => [] }  # Must NOT have delete marker at line 0 or 1
);

diff_and_check(
    "Delete 1 line, add 2 lines at same position",
    "before\ndelete1\nafter",
    "before\nadd1\nadd2\nafter",
    { added => [], modified => [1, 2], deleted => [] }  # Both are modifications
);

done_testing();
