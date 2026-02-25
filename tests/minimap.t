#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempfile);

use lib 'lib';
use Zepto::Minimap;
use Zepto::Document;
use Zepto::View;

# =============================================================================
# Helpers
# =============================================================================

sub create_temp_file {
    my ($content) = @_;
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    binmode($fh, ':utf8');
    print $fh $content;
    close $fh;
    return $filename;
}

sub create_test_state {
    my ($content, %view_opts) = @_;
    $content //= "Hello World\nLine 2\nLine 3\n";
    my $filename = create_temp_file($content);
    my $doc = Zepto::Document->load($filename);
    my $view = Zepto::View->new(document => $doc, %view_opts);
    return ($doc, $view);
}

# Create a document with N lines of varying content
sub create_multiline_doc {
    my ($num_lines) = @_;
    my $content = '';
    for my $i (1 .. $num_lines) {
        my $indent = '    ' x (($i % 4));
        $content .= "${indent}Line number $i with some content\n";
    }
    return create_test_state($content);
}

# =============================================================================
# Tests
# =============================================================================

subtest 'Constants are defined' => sub {
    is(Zepto::Minimap::MINIMAP_TOTAL_WIDTH, 8, 'Total minimap width is 8');
    is(Zepto::Minimap::MINIMAP_TEXT_COLS, 6, 'Text columns is 6');
    is(Zepto::Minimap::MINIMAP_VCS_COL, 1, 'VCS column is 1');
    is(Zepto::Minimap::MINIMAP_SEPARATOR, 1, 'Separator column is 1');
    is(Zepto::Minimap::MINIMAP_SEPARATOR + Zepto::Minimap::MINIMAP_VCS_COL + Zepto::Minimap::MINIMAP_TEXT_COLS,
       Zepto::Minimap::MINIMAP_TOTAL_WIDTH,
       'Component widths sum to total width');
};

subtest 'Empty document' => sub {
    # An "empty" file still has 1 line in Document (the empty line)
    my ($doc, $view) = create_test_state('');
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    is(ref($result), 'HASH', 'Returns hashref');
    is($result->{total_rows}, 1, 'total_rows is 1 (empty line)');
    is($result->{lines_per_row}, 1, 'lines_per_row defaults to 1');
};

subtest 'No document' => sub {
    my $result = Zepto::Minimap->compute(
        document => undef,
        view     => undef,
        height   => 20,
    );

    is(ref($result), 'HASH', 'Returns hashref');
    is(scalar @{$result->{rows}}, 0, 'No rows for undef doc');
    is($result->{total_rows}, 0, 'total_rows is 0');
};

subtest 'Single line document' => sub {
    my ($doc, $view) = create_test_state("Hello World\n");
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    is($result->{total_rows}, 1, 'One row for single line');
    is(scalar @{$result->{rows}}, 1, 'One row entry');
    is(length($result->{rows}[0]{braille}), Zepto::Minimap::MINIMAP_TEXT_COLS,
       'Braille string length matches text cols');
    is($result->{lines_per_row}, 1, 'lines_per_row is 1');
};

subtest 'Short document - 1:1 mapping' => sub {
    my ($doc, $view) = create_test_state("Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n");
    $view->{viewport_rows} = 20;

    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    is($result->{total_rows}, 5, '5 rows for 5 lines (1:1)');
    is($result->{lines_per_row}, 1, 'lines_per_row is 1 for short doc');

    # Each row should have braille data
    for my $i (0 .. 4) {
        ok(defined $result->{rows}[$i]{braille}, "Row $i has braille data");
        is(length($result->{rows}[$i]{braille}), Zepto::Minimap::MINIMAP_TEXT_COLS,
           "Row $i braille has correct length");
    }
};

subtest 'Long document - compressed mapping' => sub {
    my ($doc, $view) = create_multiline_doc(200);
    $view->{viewport_rows} = 20;

    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    is($result->{total_rows}, 20, 'Uses all available rows');
    cmp_ok($result->{lines_per_row}, '>', 1, 'lines_per_row > 1 for long doc');
    cmp_ok($result->{lines_per_row}, '==', 10, 'lines_per_row = 200/20 = 10');
    is(scalar @{$result->{rows}}, 20, '20 row entries');
};

subtest 'Viewport position calculation' => sub {
    my ($doc, $view) = create_multiline_doc(100);
    $view->{viewport_rows} = 20;
    $view->{scroll_line} = 30;
    $view->{cursor_line} = 35;

    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    # 100 lines / 20 rows = 5 lines_per_row
    is($result->{lines_per_row}, 5, 'lines_per_row = 5');

    # Viewport starts at line 30: minimap row = floor(30/5) = 6
    is($result->{viewport_start}, 6, 'Viewport start row');

    # Viewport ends at line 49: minimap row = floor(49/5) = 9
    is($result->{viewport_end}, 9, 'Viewport end row');

    # Cursor at line 35: minimap row = floor(35/5) = 7
    is($result->{cursor_row}, 7, 'Cursor row');
};

subtest 'Viewport at document start' => sub {
    my ($doc, $view) = create_multiline_doc(100);
    $view->{viewport_rows} = 20;
    $view->{scroll_line} = 0;
    $view->{cursor_line} = 0;

    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    is($result->{viewport_start}, 0, 'Viewport starts at row 0');
    is($result->{cursor_row}, 0, 'Cursor at row 0');
};

subtest 'Viewport at document end' => sub {
    my ($doc, $view) = create_multiline_doc(100);
    $view->{viewport_rows} = 20;
    $view->{scroll_line} = 80;
    $view->{cursor_line} = 99;

    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    is($result->{viewport_end}, 19, 'Viewport end clamped to last row');
    is($result->{cursor_row}, 19, 'Cursor row clamped to last row');
};

subtest 'Braille density - empty lines produce empty braille' => sub {
    my ($doc, $view) = create_test_state("\n\n\n\n\n");
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    # Empty braille = U+2800 repeated (no dots set)
    my $empty_braille = chr(0x2800) x Zepto::Minimap::MINIMAP_TEXT_COLS;
    for my $row (@{$result->{rows}}) {
        is($row->{braille}, $empty_braille, 'Empty line produces empty braille');
    }
};

subtest 'Braille density - content lines have dots set' => sub {
    my $long_line = 'x' x 80;
    my ($doc, $view) = create_test_state("$long_line\n");
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    my $braille = $result->{rows}[0]{braille};
    ok(defined $braille, 'Braille is defined');

    # All characters should have some dots set (content everywhere)
    for my $i (0 .. length($braille) - 1) {
        my $ch = substr($braille, $i, 1);
        cmp_ok(ord($ch), '>', 0x2800, "Braille char $i has dots set for full content line");
    }
};

subtest 'Braille density - indented content' => sub {
    # Line with leading spaces then content
    my ($doc, $view) = create_test_state("        content here\n");
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    my $braille = $result->{rows}[0]{braille};
    ok(defined $braille, 'Braille is defined');
    # First char should be empty (spaces), later chars should have dots
    my $first_char = substr($braille, 0, 1);
    my $last_char = substr($braille, -1, 1);
    # The last char might not have content depending on line length
    # but at least some chars should differ from empty
    my $has_content = 0;
    for my $i (0 .. length($braille) - 1) {
        my $ch = substr($braille, $i, 1);
        $has_content = 1 if ord($ch) > 0x2800;
    }
    ok($has_content, 'Indented line has some braille dots set');
};

subtest 'Braille string length is always MINIMAP_TEXT_COLS' => sub {
    # Various content lengths
    for my $content ("a\n", "a" x 200 . "\n", "  \n", "hello world\n") {
        my ($doc, $view) = create_test_state($content);
        my $result = Zepto::Minimap->compute(
            document => $doc,
            view     => $view,
            height   => 20,
        );
        is(length($result->{rows}[0]{braille}), Zepto::Minimap::MINIMAP_TEXT_COLS,
           'Braille length is consistent');
    }
};

subtest 'VCS status aggregation - no VCS returns undef' => sub {
    my ($doc, $view) = create_test_state("Hello\nWorld\n");
    # No VCS provider configured, so change/deletion status should be undef
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    for my $row (@{$result->{rows}}) {
        ok(!defined $row->{vcs}, 'VCS status is undef without VCS provider');
    }
};

subtest 'row_to_doc_line mapping' => sub {
    # 1:1 mapping
    is(Zepto::Minimap->row_to_doc_line(0, 1), 0, 'Row 0 -> line 0 (1:1)');
    is(Zepto::Minimap->row_to_doc_line(5, 1), 5, 'Row 5 -> line 5 (1:1)');

    # Compressed mapping (5 lines per row)
    is(Zepto::Minimap->row_to_doc_line(0, 5), 0, 'Row 0 -> line 0 (5:1)');
    is(Zepto::Minimap->row_to_doc_line(1, 5), 5, 'Row 1 -> line 5 (5:1)');
    is(Zepto::Minimap->row_to_doc_line(3, 5), 15, 'Row 3 -> line 15 (5:1)');

    # Fractional lines per row
    is(Zepto::Minimap->row_to_doc_line(0, 2.5), 0, 'Row 0 -> line 0 (2.5:1)');
    is(Zepto::Minimap->row_to_doc_line(2, 2.5), 5, 'Row 2 -> line 5 (2.5:1)');
};

subtest 'Height of 0 returns empty' => sub {
    my ($doc, $view) = create_test_state("Hello\n");
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 0,
    );

    is($result->{total_rows}, 0, 'No rows with height 0');
};

subtest 'Document exactly fills minimap' => sub {
    my ($doc, $view) = create_multiline_doc(20);
    $view->{viewport_rows} = 20;

    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    is($result->{total_rows}, 20, 'Exactly 20 rows');
    is($result->{lines_per_row}, 1, 'lines_per_row is 1');
};

subtest 'All row braille values are valid Unicode' => sub {
    my ($doc, $view) = create_multiline_doc(50);
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 10,
    );

    for my $i (0 .. $#{$result->{rows}}) {
        my $braille = $result->{rows}[$i]{braille};
        for my $j (0 .. length($braille) - 1) {
            my $ord = ord(substr($braille, $j, 1));
            cmp_ok($ord, '>=', 0x2800, "Row $i char $j is in braille range (lower)");
            cmp_ok($ord, '<=', 0x28FF, "Row $i char $j is in braille range (upper)");
        }
    }
};

subtest 'Compute result structure' => sub {
    my ($doc, $view) = create_multiline_doc(50);
    my $result = Zepto::Minimap->compute(
        document => $doc,
        view     => $view,
        height   => 20,
    );

    ok(exists $result->{rows}, 'Has rows');
    ok(exists $result->{viewport_start}, 'Has viewport_start');
    ok(exists $result->{viewport_end}, 'Has viewport_end');
    ok(exists $result->{cursor_row}, 'Has cursor_row');
    ok(exists $result->{lines_per_row}, 'Has lines_per_row');
    ok(exists $result->{total_rows}, 'Has total_rows');

    cmp_ok($result->{viewport_start}, '>=', 0, 'viewport_start >= 0');
    cmp_ok($result->{viewport_end}, '>=', $result->{viewport_start}, 'viewport_end >= viewport_start');
    cmp_ok($result->{cursor_row}, '>=', 0, 'cursor_row >= 0');
    cmp_ok($result->{lines_per_row}, '>', 0, 'lines_per_row > 0');
};

done_testing();
