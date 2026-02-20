#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';

use Zepto::Diff;

# =============================================================================
# Edge cases
# =============================================================================

subtest 'Empty inputs' => sub {
    my $result = Zepto::Diff->diff(undef, undef);
    is_deeply($result->{added}, [], 'Both undef: no additions');
    is_deeply($result->{modified}, [], 'Both undef: no modifications');
    is_deeply($result->{deleted}, [], 'Both undef: no deletions');

    $result = Zepto::Diff->diff('', '');
    is_deeply($result->{added}, [], 'Both empty: no additions');
    is_deeply($result->{modified}, [], 'Both empty: no modifications');
    is_deeply($result->{deleted}, [], 'Both empty: no deletions');
};

subtest 'No base (new file)' => sub {
    my $result = Zepto::Diff->diff(undef, "line1\nline2\nline3");
    is_deeply($result->{added}, [0, 1, 2], 'All lines are additions');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [], 'No deletions');

    $result = Zepto::Diff->diff('', "line1\nline2");
    is_deeply($result->{added}, [0, 1], 'Empty base: all lines added');
};

subtest 'No current (file deleted)' => sub {
    my $result = Zepto::Diff->diff("line1\nline2", undef);
    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{deleted}, [0], 'Deletion marker at start');

    $result = Zepto::Diff->diff("line1\nline2", '');
    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{deleted}, [0], 'Empty current: deletion at start');
};

# =============================================================================
# Identical content
# =============================================================================

subtest 'Identical content' => sub {
    my $text = "line1\nline2\nline3";
    my $result = Zepto::Diff->diff($text, $text);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [], 'No deletions');
};

# =============================================================================
# Simple additions
# =============================================================================

subtest 'Addition at end' => sub {
    my $base = "line1\nline2";
    my $current = "line1\nline2\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [2], 'Line 2 (0-indexed) is added');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [], 'No deletions');
};

subtest 'Addition at start' => sub {
    my $base = "line2\nline3";
    my $current = "line1\nline2\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [0], 'Line 0 is added');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [], 'No deletions');
};

subtest 'Addition in middle' => sub {
    my $base = "line1\nline3";
    my $current = "line1\nline2\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [1], 'Line 1 is added');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [], 'No deletions');
};

subtest 'Multiple additions' => sub {
    my $base = "line1\nline4";
    my $current = "line1\nline2\nline3\nline4";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [1, 2], 'Lines 1 and 2 are added');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [], 'No deletions');
};

# =============================================================================
# Simple deletions
# =============================================================================

subtest 'Deletion at end' => sub {
    my $base = "line1\nline2\nline3";
    my $current = "line1\nline2";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [1], 'Deletion after line 1');
};

subtest 'Deletion at start' => sub {
    my $base = "line1\nline2\nline3";
    my $current = "line2\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [0], 'Deletion before/at line 0');
};

subtest 'Deletion in middle' => sub {
    my $base = "line1\nline2\nline3";
    my $current = "line1\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [], 'No modifications');
    is_deeply($result->{deleted}, [0], 'Deletion after line 0');
};

# =============================================================================
# Modifications
# =============================================================================

subtest 'Single line modification' => sub {
    my $base = "line1\nline2\nline3";
    my $current = "line1\nmodified\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [1], 'Line 1 is modified');
    is_deeply($result->{deleted}, [], 'No deletions');
};

subtest 'First line modification' => sub {
    my $base = "line1\nline2\nline3";
    my $current = "modified\nline2\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [0], 'Line 0 is modified');
    is_deeply($result->{deleted}, [], 'No deletions');
};

subtest 'Last line modification' => sub {
    my $base = "line1\nline2\nline3";
    my $current = "line1\nline2\nmodified";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [2], 'Line 2 is modified');
    is_deeply($result->{deleted}, [], 'No deletions');
};

subtest 'Multiple modifications' => sub {
    my $base = "line1\nline2\nline3\nline4";
    my $current = "mod1\nline2\nmod3\nline4";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [0, 2], 'Lines 0 and 2 are modified');
    is_deeply($result->{deleted}, [], 'No deletions');
};

# =============================================================================
# Mixed operations
# =============================================================================

subtest 'Addition and modification' => sub {
    my $base = "line1\nline2";
    my $current = "modified\nline2\nnew_line";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{modified}, [0], 'Line 0 is modified');
    is_deeply($result->{added}, [2], 'Line 2 is added');
    is_deeply($result->{deleted}, [], 'No deletions');
};

subtest 'Deletion and modification' => sub {
    my $base = "line1\nline2\nline3";
    my $current = "modified\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    # Both line1->modified and line2 deletion are in same hunk
    # The deletion is absorbed into the modification (no separate marker)
    is_deeply($result->{modified}, [0], 'Line 0 is modified');
    is_deeply($result->{deleted}, [], 'Deletion absorbed into modification');
    is_deeply($result->{added}, [], 'No additions');
};

# =============================================================================
# Larger diffs
# =============================================================================

subtest 'Larger file with scattered changes' => sub {
    my $base = join("\n", map { "line$_" } 1..10);
    my $current = join("\n", (
        "modified1",  # modified
        "line2",
        "line3",
        # line4 deleted
        "line5",
        "new_line",   # added
        "line6",
        "line7",
        "modified8",  # modified
        "line9",
        "line10",
    ));
    my $result = Zepto::Diff->diff($base, $current);

    ok(grep({ $_ == 0 } @{$result->{modified}}), 'Line 0 is modified');
    ok(grep({ $_ == 7 } @{$result->{modified}}), 'Line 7 is modified');
    ok(grep({ $_ == 4 } @{$result->{added}}), 'Line 4 is added');
    ok(@{$result->{deleted}} > 0, 'Has deletions');
};

# =============================================================================
# UTF-8 content
# =============================================================================

subtest 'UTF-8 content' => sub {
    my $base = "Hello\n世界\nПривет";
    my $current = "Hello\n世界!\nПривет";  # Modified middle line
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{modified}, [1], 'UTF-8 line 1 is modified');
    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{deleted}, [], 'No deletions');
};

# =============================================================================
# Performance sanity check
# =============================================================================

subtest 'Performance on larger input' => sub {
    # Generate 1000-line files with small differences
    my @base_lines = map { "line number $_" } 1..1000;
    my @current_lines = @base_lines;
    $current_lines[100] = "modified at 100";
    $current_lines[500] = "modified at 500";
    splice(@current_lines, 250, 0, "inserted line");

    my $base = join("\n", @base_lines);
    my $current = join("\n", @current_lines);

    my $start = time();
    my $result = Zepto::Diff->diff($base, $current);
    my $elapsed = time() - $start;

    ok($elapsed < 2, "Diff completed in reasonable time (${elapsed}s)");
    ok(@{$result->{modified}} >= 2, 'Found modifications');
    ok(@{$result->{added}} >= 1, 'Found additions');
};

# =============================================================================
# Whitespace-only modifications
# =============================================================================

subtest 'Whitespace-only modification: indentation change' => sub {
    my $base = "line1\n  indented\nline3";
    my $current = "line1\n    indented\nline3";  # Changed indentation
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{added}, [], 'No additions');
    is_deeply($result->{modified}, [], 'Not in regular modified');
    is_deeply($result->{modified_whitespace}, [1], 'Line 1 is whitespace-only modified');
    is_deeply($result->{deleted}, [], 'No deletions');
};

subtest 'Whitespace-only modification: trailing whitespace' => sub {
    my $base = "line1\nhello\nline3";
    my $current = "line1\nhello   \nline3";  # Added trailing spaces
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{modified}, [], 'Not in regular modified');
    is_deeply($result->{modified_whitespace}, [1], 'Line 1 is whitespace-only modified');
};

subtest 'Whitespace-only modification: tabs to spaces' => sub {
    my $base = "line1\n\tindented\nline3";
    my $current = "line1\n    indented\nline3";  # Tab to spaces
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{modified}, [], 'Not in regular modified');
    is_deeply($result->{modified_whitespace}, [1], 'Line 1 is whitespace-only modified');
};

subtest 'Content modification is NOT whitespace-only' => sub {
    my $base = "line1\nhello world\nline3";
    my $current = "line1\nhello earth\nline3";
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{modified}, [1], 'Line 1 is content-modified');
    is_deeply($result->{modified_whitespace}, [], 'Not whitespace-only');
};

subtest 'Mixed content and whitespace modifications' => sub {
    my $base = "line1\nhello\n  world\nline4";
    my $current = "line1\ngoodbye\n    world\nline4";  # line2: content, line3: whitespace
    my $result = Zepto::Diff->diff($base, $current);

    ok(grep({ $_ == 1 } @{$result->{modified}}), 'Line 1 is content-modified');
    ok(grep({ $_ == 2 } @{$result->{modified_whitespace}}), 'Line 2 is whitespace-only modified');
};

subtest 'Multiple whitespace-only modifications' => sub {
    my $base = "  a\nb\n  c\nd";
    my $current = "    a\nb\n    c\nd";  # Reindented lines 0 and 2
    my $result = Zepto::Diff->diff($base, $current);

    is_deeply($result->{modified}, [], 'No content modifications');
    is_deeply($result->{modified_whitespace}, [0, 2], 'Lines 0 and 2 are whitespace-only');
};

subtest 'Hunk with different line counts is not whitespace-only' => sub {
    # Even if whitespace is the only non-structural change, adding/removing lines
    # means it is not a simple whitespace modification
    my $base = "line1\nhello world\nline3";
    my $current = "line1\nhello\nworld\nline3";  # Split into two lines
    my $result = Zepto::Diff->diff($base, $current);

    # This should NOT be whitespace-only since line count changed
    is_deeply($result->{modified_whitespace}, [], 'Line split is not whitespace-only');
};

done_testing();
