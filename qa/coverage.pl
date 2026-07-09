#!/usr/bin/env perl
# qa/coverage.pl — documented-vs-scripted QA coverage report.
#
# Scans qa/NN_*.txt for documented test case IDs (lines matching
# "ID:  QA-TAG-NNN") and qa/scripts/tier1/*.sh + qa/scripts/tier2/*.sh for
# their "# QA-TAG-NNN:" header comment, then reports how many documented
# IDs have at least one executable script.
#
# Usage: perl qa/coverage.pl
#
# Always exits 0 — this is a reporting tool, not a test gate. Run via
# `make qa-coverage`.

use strict;
use warnings;
use FindBin qw($RealBin);
use File::Basename qw(basename);

my $qa_dir = $RealBin;

# --- 1. Collect documented IDs from qa/NN_*.txt, in file order -------------

my @doc_files = sort glob("$qa_dir/[0-9][0-9]_*.txt");

my %documented;      # id => source filename
my @file_order;      # preserves file scan order
my %ids_by_file;      # filename => [ids in file order]

for my $path (@doc_files) {
    my $fname = basename($path);
    push @file_order, $fname;
    $ids_by_file{$fname} = [];

    open my $fh, '<', $path or die "coverage.pl: cannot open $path: $!\n";
    while (my $line = <$fh>) {
        if ($line =~ /^ID:\s*(QA-[A-Z0-9]+-[0-9]+)\s*$/) {
            my $id = $1;
            if (exists $documented{$id}) {
                warn "coverage.pl: WARNING duplicate documented ID $id in $fname (first seen in $documented{$id})\n";
                next;
            }
            $documented{$id} = $fname;
            push @{ $ids_by_file{$fname} }, $id;
        }
    }
    close $fh;
}

# --- 2. Collect scripted IDs from qa/scripts/tier{1,2}/*.sh -----------------

my %scripted;   # id => [ { tier => 'tier1'|'tier2', script => basename }, ... ]

for my $tier (qw(tier1 tier2)) {
    my @scripts = sort glob("$qa_dir/scripts/$tier/*.sh");
    for my $path (@scripts) {
        my $script = basename($path);
        open my $fh, '<', $path or die "coverage.pl: cannot open $path: $!\n";
        my $id;
        while (my $line = <$fh>) {
            if ($line =~ /(QA-[A-Z0-9]+-[0-9]+)/) {
                $id = $1;
                last;
            }
        }
        close $fh;

        if (!defined $id) {
            warn "coverage.pl: WARNING no QA-ID found in $tier/$script\n";
            next;
        }

        push @{ $scripted{$id} }, { tier => $tier, script => $script };
    }
}

# --- 3. Compute coverage -----------------------------------------------------

my @all_ids = sort keys %documented;
my $total = scalar @all_ids;
my $covered = grep { exists $scripted{$_} } @all_ids;
my $pct = $total ? sprintf('%.1f', 100 * $covered / $total) : '0.0';

print "QA coverage: documented test cases with an executable script\n";
print "=" x 70, "\n";
printf "TOTAL: %d/%d (%s%%)\n\n", $covered, $total, $pct;

# --- 4. List uncovered IDs, grouped by source file --------------------------

my $any_uncovered = 0;
for my $fname (@file_order) {
    my @ids = @{ $ids_by_file{$fname} };
    my @uncovered = grep { !exists $scripted{$_} } @ids;
    next unless @uncovered;
    $any_uncovered = 1;
    my $file_total = scalar @ids;
    my $file_covered = $file_total - scalar(@uncovered);
    printf "%-38s %3d/%3d covered, %d missing\n", $fname, $file_covered, $file_total, scalar(@uncovered);
    for my $id (@uncovered) {
        print "    [no script] $id\n";
    }
}

print "\nAll documented IDs have at least one script.\n" unless $any_uncovered;

# --- 5. Flag scripted IDs with no matching documented case (orphan scripts) -

my @orphans = grep { !exists $documented{$_} } sort keys %scripted;
if (@orphans) {
    print "\n", "-" x 70, "\n";
    print "Scripts referencing an ID with no documented test case:\n";
    for my $id (@orphans) {
        for my $entry (@{ $scripted{$id} }) {
            print "    [$entry->{tier}] $entry->{script} -> $id (undocumented)\n";
        }
    }
}

# --- 6. Flag duplicate script IDs (known anomalies; informational only) ----

my @dupes = grep { scalar(@{ $scripted{$_} }) > 1 } sort keys %scripted;
if (@dupes) {
    print "\n", "-" x 70, "\n";
    print "IDs with more than one script (see CATALOG.md 'Known anomalies'):\n";
    for my $id (@dupes) {
        for my $entry (@{ $scripted{$id} }) {
            print "    $id -> [$entry->{tier}] $entry->{script}\n";
        }
    }
}

print "\n", "=" x 70, "\n";
printf "Summary: %d documented, %d scripted-unique, %d covered (%s%%), %d orphan scripts, %d duplicate-ID groups\n",
    $total, scalar(keys %scripted), $covered, $pct, scalar(@orphans), scalar(@dupes);

exit 0;
