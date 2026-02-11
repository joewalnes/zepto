#!/usr/bin/env perl
# Generate .expected files from actual grammar output
# Usage: perl scripts/generate_expected.pl [sample_file]
#        If no file specified, processes all sample files

use strict;
use warnings;
use File::Basename;
use File::Spec;

my $script_dir = dirname(__FILE__);
my $lib_dir = File::Spec->catdir($script_dir, '..', 'lib');
my $samples_dir = File::Spec->catdir($script_dir, '..', 'tests', 'samples');

unshift @INC, $lib_dir;

require Zepto::Highlighter;
require Zepto::Syntax::Base;

my @files;
if (@ARGV) {
    @files = @ARGV;
} else {
    opendir(my $dh, $samples_dir) or die "Cannot open $samples_dir: $!";
    @files = map { File::Spec->catfile($samples_dir, $_) }
             grep { !/\.expected$/ && -f File::Spec->catfile($samples_dir, $_) }
             readdir($dh);
    closedir($dh);
}

for my $sample_path (@files) {
    $sample_path = File::Spec->catfile($samples_dir, $sample_path) unless -f $sample_path;

    my $base = basename($sample_path);
    $base =~ s/\.[^.]+$// if $base =~ /\./;
    my $expected_path = File::Spec->catfile(dirname($sample_path), "${base}.expected");

    print "Processing $sample_path -> $expected_path\n";

    my $highlighter = Zepto::Highlighter->new();
    $highlighter->set_file($sample_path);

    open(my $fh, '<', $sample_path) or die "Cannot open $sample_path: $!";
    my @lines = <$fh>;
    close($fh);

    if (!$highlighter->has_grammar && @lines > 0) {
        $highlighter->detect_from_shebang($lines[0]);
    }

    if (!$highlighter->has_grammar) {
        warn "No grammar for $sample_path, skipping\n";
        next;
    }

    my $grammar_name = $highlighter->grammar_name // 'unknown';

    open(my $out, '>', $expected_path) or die "Cannot write $expected_path: $!";
    print $out "# Expected syntax highlighting for " . basename($sample_path) . "\n";
    print $out "# Generated from $grammar_name grammar\n";
    print $out "# Format: <TYPE>text</TYPE> where TYPE is the token type\n";
    print $out "\n";

    for my $i (0 .. $#lines) {
        chomp(my $line = $lines[$i]);
        my ($tokens, $state) = $highlighter->tokenize_line($line, $i);

        # Build expected line with token markup
        my $expected_line = '';
        my $pos = 0;

        # Sort tokens by start position
        my @sorted = sort { $a->{start} <=> $b->{start} } @$tokens;

        for my $token (@sorted) {
            # Add any plain text before this token
            if ($token->{start} > $pos) {
                $expected_line .= substr($line, $pos, $token->{start} - $pos);
            }

            # Add the token with markup
            my $text = substr($line, $token->{start}, $token->{end} - $token->{start});
            my $type = uc($token->{type});
            $expected_line .= "<$type>$text</$type>";
            $pos = $token->{end};
        }

        # Add remaining plain text
        if ($pos < length($line)) {
            $expected_line .= substr($line, $pos);
        }

        print $out "$expected_line\n";
    }

    close($out);
    print "  Written: $expected_path\n";
}

print "Done.\n";
