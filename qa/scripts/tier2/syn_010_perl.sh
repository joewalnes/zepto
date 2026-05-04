#!/usr/bin/env bash
# QA-SYN-010: Perl syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-010: Perl syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn010.pl" '#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;

# Configuration constants
my $VERSION = "3.2.1";
my $MAX_SIZE = 1024 * 1024;
my @colors = ("red", "green", "blue");
my %config = (
    debug   => 0,
    verbose => 1,
    name    => "zepto",
);

sub process_file {
    my ($filename, $opts) = @_;
    return unless -f $filename;

    open(my $fh, "<", $filename) or die "Cannot open: $!";
    while (my $line = <$fh>) {
        chomp $line;
        if ($line =~ /^#\s*(\w+):\s*(.+)$/) {
            my ($key, $val) = ($1, $2);
            $config{$key} = $val;
        }
    }
    close $fh;
}

# Main
for my $file (@ARGV) {
    print "Processing: $file\n";
    process_file($file, \%config);
}

print "Done. Version $VERSION\n";')
qa_start "$file"

shot="$QA_TMPDIR/perl_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Perl script in a terminal text editor with syntax highlighting. Verify ALL of these: (1) Keywords like 'use', 'my', 'sub', 'return', 'unless', 'while', 'if', 'for', 'open', 'close', 'print', 'die' are highlighted in a distinct color. (2) Strings in double quotes like '3.2.1', 'red' and the print strings are in a string color. (3) Variables with sigils ($filename, @colors, %config, $fh) are highlighted — the $ @ % sigils should be colored. (4) The comment lines starting with # are in a muted/gray color. (5) The regex /^#\\s*.../ is highlighted distinctly. (6) Numbers like 1024, 0, 1 are in their own color. (7) The shebang line is highlighted. (8) At least 4 distinct colors are used." \
    "Perl syntax highlighting with keywords, sigils, regex, strings"

qa_keys "ctrl-q"

qa_summary
