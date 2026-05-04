#!/usr/bin/env bash
# QA-SYN-014: Perl s/// regex highlighted distinctly
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-014: Perl regex s/// highlighting (visual)"

file=$(qa_tmpfile_nl "syn014.pl" '#!/usr/bin/env perl
use strict;
use warnings;

my $text = "Hello World 2025";

# Simple substitution
$text =~ s/World/Perl/g;

# Regex with character classes
$text =~ s/[0-9]+/2026/;

# Transliteration
(my $lower = $text) =~ tr/A-Z/a-z/;

# Match with captures
if ($text =~ m/^(\w+)\s+(\w+)/) {
    my ($first, $second) = ($1, $2);
    print "Matched: $first $second\n";
}

print "Result: $text\n";')
qa_start "$file"

shot="$QA_TMPDIR/perl_regex.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Perl script in a terminal text editor with syntax highlighting. Verify: (1) The s/.../.../g substitution expressions are highlighted — the regex pattern inside the slashes has a distinct color from surrounding code. (2) The tr/.../.../  transliteration is also highlighted. (3) At least 3 distinct colors are used across keywords, strings, regex patterns, and comments." \
    "Perl s/// and tr/// regex highlighted distinctly"

qa_keys "ctrl-q"

qa_summary
