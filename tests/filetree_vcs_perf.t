#!/usr/bin/env perl
# Correctness + performance regression test for FileTree's VCS status
# propagation to unloaded (collapsed) directories.
#
# Background: _dir_vcs_status_from_hash() used to re-scan the *entire*
# changed-files hash (S entries) for every unloaded directory node (D of
# them) — O(D * S). The fix pre-indexes the changed-files hash by every
# ancestor directory ONCE per propagation pass (_build_vcs_dir_index,
# O(S * depth)), then looks up each directory's status in O(1).
#
# This test reconstructs the OLD algorithm verbatim (as it existed in
# FileTree.pm before the fix) as local subs below, so it can assert
# correctness (old vs. new produce byte-identical results) and performance
# (old is demonstrably slow at this workload size, new comfortably isn't)
# in the same run, without needing to check out a prior git revision.
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Cwd ();

use lib 'lib';
use Zepto::FileTree;

# =============================================================================
# OLD algorithm, reconstructed verbatim from pre-fix FileTree.pm for
# side-by-side comparison. DO NOT "clean this up" to match the new code —
# the whole point is that it's an independent, unmodified reference.
# =============================================================================

my %OLD_VCS_PRIORITY = (
    modified  => 4,
    added     => 3,
    untracked => 2,
    staged    => 1,
);

sub old_dir_vcs_status_from_hash {
    my ($dir_path, $statuses) = @_;
    my $prefix = "$dir_path/";
    my $worst_priority = 0;
    my $worst_status;

    for my $path (keys %$statuses) {
        next unless index($path, $prefix) == 0;
        my $status = $statuses->{$path};
        my $p = $OLD_VCS_PRIORITY{$status} // 0;
        if ($p > $worst_priority) {
            $worst_priority = $p;
            $worst_status = $status;
        }
    }

    return $worst_status;
}

sub old_propagate_dir_status {
    my ($nodes, $statuses) = @_;

    for my $node (@$nodes) {
        next unless $node->{is_dir};

        if (defined $node->{children}) {
            old_propagate_dir_status($node->{children}, $statuses);

            my $worst_priority = 0;
            my $worst_status;

            for my $child (@{$node->{children}}) {
                my $status = $child->{vcs_status};
                next unless defined $status;
                my $p = $OLD_VCS_PRIORITY{$status} // 0;
                if ($p > $worst_priority) {
                    $worst_priority = $p;
                    $worst_status = $status;
                }
            }

            $node->{vcs_status} = $worst_status;
        } else {
            $node->{vcs_status} = old_dir_vcs_status_from_hash($node->{path}, $statuses);
        }
    }
}

# =============================================================================
# Test fixture builders
# =============================================================================

# Build a real directory tree with $n top-level (unloaded) directories under
# a fresh tmpdir, and return a FileTree over it. Each dir gets one file so
# it's not pruned as empty by anything that cares.
sub build_tree {
    my ($n) = @_;
    my $tmpdir = Cwd::realpath(tempdir(CLEANUP => 1));

    for my $i (1 .. $n) {
        make_path("$tmpdir/dir_$i");
        open my $fh, '>', "$tmpdir/dir_$i/placeholder.txt" or die $!;
        print $fh "x\n";
        close $fh;
    }

    return Zepto::FileTree->new(root_path => $tmpdir);
}

# Collect { dir_path => vcs_status } for every directory node in the tree
# (recursively, though in these fixtures only the top level is populated —
# children stay unloaded/undef since nothing calls expand()).
sub collect_dir_statuses {
    my ($nodes, $out) = @_;
    $out //= {};
    for my $node (@$nodes) {
        next unless $node->{is_dir};
        $out->{$node->{path}} = $node->{vcs_status};
        collect_dir_statuses($node->{children}, $out) if defined $node->{children};
    }
    return $out;
}

# =============================================================================
# Correctness: old vs. new produce identical results
# =============================================================================

subtest 'Old and new algorithms agree — no matching changes' => sub {
    my $tree = build_tree(6);
    my %statuses = (
        'totally/unrelated/file.txt' => 'modified',
    );

    $tree->{_vcs_statuses} = \%statuses;
    old_propagate_dir_status($tree->nodes(), \%statuses);
    my $old_result = collect_dir_statuses($tree->nodes());

    # Reset and run the new (current, fixed) code path
    for my $node (@{ $tree->nodes() }) { $node->{vcs_status} = undef; }
    $tree->_propagate_dir_status($tree->nodes());
    my $new_result = collect_dir_statuses($tree->nodes());

    is_deeply($new_result, $old_result, 'identical dir statuses (all undef — no matches)');
    ok((scalar grep { defined } values %$new_result) == 0, 'sanity: really no matches found');
};

subtest 'Old and new algorithms agree — overlapping changes, mixed priority' => sub {
    my $tree = build_tree(6);
    my %statuses = (
        'dir_1/a.txt'          => 'staged',
        'dir_1/nested/b.txt'   => 'modified',   # higher priority, same dir_1
        'dir_2/c.txt'          => 'added',
        'dir_3/nested/deep/d.txt' => 'untracked',
        'dir_5/e.txt'          => 'staged',
        'unrelated/f.txt'      => 'modified',   # doesn't match any dir_N
        # dir_4 and dir_6 have no changes at all
    );

    $tree->{_vcs_statuses} = \%statuses;
    old_propagate_dir_status($tree->nodes(), \%statuses);
    my $old_result = collect_dir_statuses($tree->nodes());

    for my $node (@{ $tree->nodes() }) { $node->{vcs_status} = undef; }
    $tree->_propagate_dir_status($tree->nodes());
    my $new_result = collect_dir_statuses($tree->nodes());

    is_deeply($new_result, $old_result, 'identical dir statuses across mixed-priority overlapping changes');

    # Spot-check expected values directly (not just old==new, in case both
    # were wrong in the same way)
    is($new_result->{dir_1}, 'modified', 'dir_1 picks worst (modified) over staged sibling');
    is($new_result->{dir_2}, 'added', 'dir_2 reflects its single added file');
    is($new_result->{dir_3}, 'untracked', 'dir_3 sees change nested two levels deep');
    is($new_result->{dir_4}, undef, 'dir_4 has no changes');
    is($new_result->{dir_5}, 'staged', 'dir_5 reflects its single staged file');
    is($new_result->{dir_6}, undef, 'dir_6 has no changes');
};

subtest 'Old and new algorithms agree — empty status hash' => sub {
    my $tree = build_tree(4);
    my %statuses = ();

    $tree->{_vcs_statuses} = \%statuses;
    old_propagate_dir_status($tree->nodes(), \%statuses);
    my $old_result = collect_dir_statuses($tree->nodes());

    for my $node (@{ $tree->nodes() }) { $node->{vcs_status} = undef; }
    $tree->_propagate_dir_status($tree->nodes());
    my $new_result = collect_dir_statuses($tree->nodes());

    is_deeply($new_result, $old_result, 'identical (all undef) with no VCS changes at all');
};

# =============================================================================
# Performance: new algorithm is dramatically faster, and comfortably under
# a bound the old algorithm demonstrably violates, at more than one scale.
# =============================================================================

sub build_statuses {
    my ($s) = @_;
    my %statuses;
    my @kinds = qw(modified added untracked staged);
    # Worst case for the old linear scan: none of these paths match any of
    # the real directories on disk, so every one of the S entries must be
    # examined (and rejected) for every one of the D directories.
    for my $i (1 .. $s) {
        $statuses{"unrelated_path_$i/file_$i.txt"} = $kinds[$i % 4];
    }
    return \%statuses;
}

for my $scale ([300, 3000, 30], [600, 6000, 150]) {
    my ($d, $s, $new_bound_ms) = @$scale;

    subtest "Performance at D=$d, S=$s" => sub {
        my $tree = build_tree($d);
        my $statuses = build_statuses($s);
        $tree->{_vcs_statuses} = $statuses;

        my $t0 = time();
        old_propagate_dir_status($tree->nodes(), $statuses);
        my $old_ms = (time() - $t0) * 1000;

        for my $node (@{ $tree->nodes() }) { $node->{vcs_status} = undef; }

        my $t1 = time();
        $tree->_propagate_dir_status($tree->nodes());
        my $new_ms = (time() - $t1) * 1000;

        diag sprintf("D=%d S=%d: old=%.2fms new=%.2fms (%.1fx faster)",
            $d, $s, $old_ms, $new_ms, $new_ms > 0 ? $old_ms / $new_ms : 0);

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

done_testing();
