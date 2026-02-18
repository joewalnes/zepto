#!/usr/bin/env perl
# =============================================================================
# Regenerate .expected files from current tokenizer output
# =============================================================================
#
# Usage:
#   scripts/regenerate_expected.pl              # Regenerate all
#   scripts/regenerate_expected.pl sample.pl   # Regenerate specific file
#
# =============================================================================

use strict;
use warnings;
use File::Basename;
use File::Spec;

# Find project paths
my $script_dir = dirname(__FILE__);
my $project_root = File::Spec->catdir($script_dir, '..');
my $lib_dir = File::Spec->catdir($project_root, 'lib');
my $samples_dir = File::Spec->catdir($project_root, 'tests', 'samples');

# Add lib to path
unshift @INC, $lib_dir;

require Zepto::Highlighter;
require Zepto::Syntax::Base;

# Token types use string values, map them to uppercase for tags
my %type_names = (
    'keyword'     => 'KEYWORD',
    'string'      => 'STRING',
    'number'      => 'NUMBER',
    'comment'     => 'COMMENT',
    'operator'    => 'OPERATOR',
    'type'        => 'TYPE',
    'function'    => 'FUNCTION',
    'variable'    => 'VARIABLE',
    'constant'    => 'CONSTANT',
    'regex'       => 'REGEX',
    'tag'         => 'TAG',
    'attribute'   => 'ATTRIBUTE',
    'heading'     => 'HEADING',
    'punctuation' => 'PUNCTUATION',
    'escape'      => 'ESCAPE',
);

# Get list of sample files to process
my @sample_files;
if (@ARGV) {
    for my $arg (@ARGV) {
        # Handle both bare filenames and full paths
        my $basename = basename($arg);
        my $full_path = File::Spec->catfile($samples_dir, $basename);
        if (-f $full_path) {
            push @sample_files, $basename;
        } elsif (-f $arg) {
            push @sample_files, $basename;
        } else {
            die "Sample file not found: $arg\n";
        }
    }
} else {
    # Get all sample files (excluding .expected files)
    opendir(my $dh, $samples_dir) or die "Cannot open samples directory: $!";
    @sample_files = grep { !/\.expected$/ && -f File::Spec->catfile($samples_dir, $_) } readdir($dh);
    closedir($dh);
}

for my $sample_file (sort @sample_files) {
    my $sample_path = File::Spec->catfile($samples_dir, $sample_file);

    # Determine expected file path
    my $base = $sample_file;
    $base =~ s/\.[^.]+$// if $sample_file =~ /\./;
    my $expected_path = File::Spec->catfile($samples_dir, "${base}.expected");

    # Create highlighter
    my $highlighter = Zepto::Highlighter->new();
    $highlighter->set_file($sample_path);

    # Read sample file
    open(my $fh, '<', $sample_path) or die "Cannot open $sample_path: $!";
    my @lines = <$fh>;
    close($fh);

    # Detect from shebang if needed
    if (!$highlighter->has_grammar && @lines > 0) {
        $highlighter->detect_from_shebang($lines[0]);
    }

    if (!$highlighter->has_grammar) {
        print "SKIP: No grammar available for $sample_file\n";
        next;
    }

    # Get grammar name for header
    my $grammar_name = $highlighter->grammar_name;

    # Generate expected output
    my @output;
    push @output, "# Expected syntax highlighting for $sample_file";
    push @output, "# Generated from $grammar_name grammar";
    push @output, "# Format: <TYPE>text</TYPE> where TYPE is the token type";
    push @output, "";

    for my $i (0 .. $#lines) {
        chomp(my $line = $lines[$i]);
        my ($tokens, $state) = $highlighter->tokenize_line($line, $i);

        # Sort tokens by start position
        my @sorted_tokens = sort { $a->{start} <=> $b->{start} } @$tokens;

        # Build output line with tags
        my $output_line = "";
        my $pos = 0;

        for my $token (@sorted_tokens) {
            my $start = $token->{start};
            my $end = $token->{end};
            my $type = $token->{type};

            # Add any untagged text before this token (escape special chars)
            if ($start > $pos) {
                my $gap = substr($line, $pos, $start - $pos);
                $gap =~ s/&/&amp;/g;
                $gap =~ s/</&lt;/g;
                $gap =~ s/>/&gt;/g;
                $output_line .= $gap;
            }

            # Add tagged text
            my $text = substr($line, $start, $end - $start);
            my $type_name = $type_names{$type} // 'UNKNOWN';

            # Escape special XML characters in text
            $text =~ s/&/&amp;/g;
            $text =~ s/</&lt;/g;
            $text =~ s/>/&gt;/g;

            $output_line .= "<$type_name>$text</$type_name>";
            $pos = $end;
        }

        # Add any remaining untagged text (also escape special chars)
        if ($pos < length($line)) {
            my $remaining = substr($line, $pos);
            $remaining =~ s/&/&amp;/g;
            $remaining =~ s/</&lt;/g;
            $remaining =~ s/>/&gt;/g;
            $output_line .= $remaining;
        }

        push @output, $output_line;
    }

    # Write expected file
    open(my $ofh, '>', $expected_path) or die "Cannot write $expected_path: $!";
    print $ofh join("\n", @output) . "\n";
    close($ofh);

    print "Generated: $expected_path\n";
}

print "Done.\n";
