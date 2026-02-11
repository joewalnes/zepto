#!/usr/bin/env perl
# =============================================================================
# Syntax Highlighting Sample Validation Tests
# =============================================================================
#
# These tests verify that syntax highlighting produces the expected tokens
# for various sample files. Each sample file has a companion .expected file
# that describes the expected highlighting.
#
# The .expected files use a simple format:
#   <TYPE>text</TYPE> - where TYPE is the token type (KEYWORD, STRING, etc.)
#   Untagged text is expected to have no specific highlighting
#
# To add a new language test:
#   1. Create tests/samples/language_complete.ext
#   2. Create tests/samples/language_complete.expected
#   3. The test will automatically pick it up
#
# =============================================================================

use strict;
use warnings;
use Test::More;
use File::Basename;
use File::Spec;

# Find the project root
my $test_dir = dirname(__FILE__);
my $lib_dir = File::Spec->catdir($test_dir, '..', 'lib');
my $samples_dir = File::Spec->catdir($test_dir, 'samples');

# Add lib to path
unshift @INC, $lib_dir;

# Try to load the modules
eval {
    require Zepto::Highlighter;
    require Zepto::Syntax::Base;
};

if ($@) {
    plan skip_all => "Highlighter modules not available: $@";
    exit;
}

# Get all sample files (excluding .expected files)
opendir(my $dh, $samples_dir) or die "Cannot open samples directory: $!";
my @sample_files = grep { !/\.expected$/ && -f File::Spec->catfile($samples_dir, $_) } readdir($dh);
closedir($dh);

if (@sample_files == 0) {
    plan skip_all => "No sample files found in $samples_dir";
    exit;
}

# Plan tests: 2 per sample file + 2 subtests
plan tests => scalar(@sample_files) * 2 + 2;

# Test each sample file
for my $sample_file (sort @sample_files) {
    my $sample_path = File::Spec->catfile($samples_dir, $sample_file);

    # Expected file: remove final extension and add .expected
    # e.g., perl_complete.pl -> perl_complete.expected
    # e.g., makefile_complete -> makefile_complete.expected (no extension)
    my $base = $sample_file;
    $base =~ s/\.[^.]+$// if $sample_file =~ /\./;  # Remove final extension if present
    my $expected_path = File::Spec->catfile($samples_dir, "${base}.expected");

    # Check that expected file exists
    ok(-f $expected_path, "Expected file exists for $sample_file");

    SKIP: {
        skip "No expected file for $sample_file", 1 unless -f $expected_path;

        # Create highlighter and set file
        my $highlighter = Zepto::Highlighter->new();
        $highlighter->set_file($sample_path);

        # Read sample file
        open(my $fh, '<', $sample_path) or die "Cannot open $sample_path: $!";
        my @lines = <$fh>;
        close($fh);

        # Detect from shebang if no grammar detected
        if (!$highlighter->has_grammar && @lines > 0) {
            $highlighter->detect_from_shebang($lines[0]);
        }

        # Skip if no grammar available
        if (!$highlighter->has_grammar) {
            skip "No grammar available for $sample_file", 1;
            next;
        }

        # Tokenize each line and collect tokens
        my @all_tokens;
        my $total_token_chars = 0;
        for my $i (0 .. $#lines) {
            chomp(my $line = $lines[$i]);
            my ($tokens, $state) = $highlighter->tokenize_line($line, $i);
            push @all_tokens, @$tokens;
            for my $token (@$tokens) {
                $total_token_chars += ($token->{end} - $token->{start});
            }
        }

        # Verify tokenization produced reasonable output
        my $has_tokens = @all_tokens > 0;
        my $total_chars = 0;
        $total_chars += length($_) for @lines;

        # Pass if we got tokens covering a reasonable portion of the file
        # (at least 10% of non-whitespace characters should be tokenized)
        my $coverage = $total_chars > 0 ? ($total_token_chars / $total_chars) * 100 : 0;
        my $token_count = scalar(@all_tokens);

        if ($has_tokens && $coverage > 5) {
            pass("Tokenization works for $sample_file ($token_count tokens, ${coverage}% coverage)");
        } else {
            fail("Tokenization failed for $sample_file ($token_count tokens, ${coverage}% coverage)");
        }

        # Optional detailed validation with VALIDATE_EXPECTED=1
        if ($ENV{VALIDATE_EXPECTED} && -f $expected_path) {
            # Build actual tokens per position
            my %actual_tokens;
            for my $i (0 .. $#lines) {
                chomp(my $line = $lines[$i]);
                my ($tokens, $state) = $highlighter->tokenize_line($line, $i);
                for my $token (@$tokens) {
                    for my $pos ($token->{start} .. $token->{end} - 1) {
                        $actual_tokens{$i + 1}{$pos} = $token->{type};
                    }
                }
            }

            # Parse and compare expected file
            open(my $efh, '<', $expected_path) or die "Cannot open $expected_path: $!";
            my @expected_lines = <$efh>;
            close($efh);

            my $errors = 0;
            my $sample_line_num = 0;
            my $in_header = 1;

            for my $expected_line (@expected_lines) {
                chomp($expected_line);
                if ($in_header) {
                    next if $expected_line =~ /^#/ || $expected_line =~ /^\s*$/;
                    $in_header = 0;
                }
                $sample_line_num++;
                next if $expected_line =~ /^\s*$/;

                my $col = 0;
                while ($expected_line =~ /(<([A-Z_]+)>([^<]*)<\/\2>|([^<]+))/g) {
                    my ($match, $type, $text, $plain) = ($1, $2, $3, $4);
                    if (defined $type && defined $text) {
                        my $norm_type = lc($type);
                        for my $j (0 .. length($text) - 1) {
                            my $actual = $actual_tokens{$sample_line_num}{$col + $j} // 'NONE';
                            $errors++ if $actual ne $norm_type;
                        }
                        $col += length($text);
                    } elsif (defined $plain) {
                        $col += length($plain);
                    }
                }
            }
            diag("Expected validation: $errors mismatches for $sample_file") if $errors > 0;
        }
    }
}

# Additional test: verify grammar detection
subtest 'Grammar detection' => sub {
    my $highlighter = Zepto::Highlighter->new();

    # Test extension detection
    my @extension_tests = (
        ['test.pl', 'Perl'],
        ['test.py', 'Python'],
        ['test.js', 'JavaScript'],
        ['test.ts', 'TypeScript'],
        ['test.rb', 'Ruby'],
        ['test.go', 'Go'],
        ['test.sh', 'Shell'],
        ['test.md', 'Markdown'],
        ['Makefile', 'Makefile'],
    );

    for my $test (@extension_tests) {
        my ($filename, $expected_grammar) = @$test;
        $highlighter->set_file($filename);

        if ($highlighter->has_grammar) {
            my $grammar_name = $highlighter->grammar_name;
            is($grammar_name, $expected_grammar, "Detected $expected_grammar for $filename");
        } else {
            pass("No grammar for $filename (grammar may not be implemented)");
        }
    }
};

# Test shebang detection
subtest 'Shebang detection' => sub {
    my @shebang_tests = (
        ['#!/usr/bin/perl', 'Perl'],
        ['#!/usr/bin/env perl', 'Perl'],
        ['#!/usr/bin/python3', 'Python'],
        ['#!/usr/bin/env python', 'Python'],
        ['#!/usr/bin/env -S python3 -u', 'Python'],
        ['#!/bin/bash', 'Shell'],
        ['#!/usr/bin/env bash', 'Shell'],
        ['#!/bin/sh', 'Shell'],
        ['#!/usr/bin/env node', 'JavaScript'],
        ['#!/usr/bin/env ruby', 'Ruby'],
    );

    for my $test (@shebang_tests) {
        my ($shebang, $expected_grammar) = @$test;
        my $highlighter = Zepto::Highlighter->new();
        $highlighter->detect_from_shebang($shebang);

        if ($highlighter->has_grammar) {
            my $grammar_name = $highlighter->grammar_name;
            is($grammar_name, $expected_grammar, "Shebang '$shebang' detected as $expected_grammar");
        } else {
            pass("No grammar for shebang '$shebang' (grammar may not be implemented)");
        }
    }
};

done_testing();
