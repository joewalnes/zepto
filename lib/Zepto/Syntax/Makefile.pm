package Zepto::Syntax::Makefile;
# =============================================================================
# Makefile Syntax Grammar
# =============================================================================
#
# Highlights: targets, variables, comments, shell commands, special variables
#
# Note: Makefile syntax is complex due to mixing make syntax with shell.
# This is a simplified highlighter focusing on common patterns.
#
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

# Make built-in functions
my $FUNCTIONS = qr/\$\((?:
    subst | patsubst | strip | findstring | filter | filter-out |
    sort | word | wordlist | words | firstword | lastword |
    dir | notdir | suffix | basename | addsuffix | addprefix |
    join | wildcard | realpath | abspath |
    if | or | and | foreach | file | call | value | eval |
    origin | flavor | error | warning | info | shell
)\b/x;

# Automatic variables
my $AUTO_VARS = qr/\$[@%<?^+*]/;

# Special targets
my $SPECIAL_TARGETS = qr/^\.(PHONY|SUFFIXES|DEFAULT|PRECIOUS|INTERMEDIATE|SECONDARY|SECONDEXPANSION|DELETE_ON_ERROR|IGNORE|LOW_RESOLUTION_TIME|SILENT|EXPORT_ALL_VARIABLES|NOTPARALLEL|ONESHELL|POSIX)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Comment
    if ($line =~ /^(\s*)(#.*)/) {
        my $indent = $1;
        my $comment = $2;
        push @tokens, _token(length($indent), $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Recipe line (starts with tab)
    if ($line =~ /^\t/) {
        # This is a shell command - highlight as string with variables
        push @tokens, _token(0, 1, TOKEN_PUNCTUATION);  # The tab
        $pos = 1;

        while ($pos < $len) {
            my $rest = substr($line, $pos);

            # Make variables $(VAR) or ${VAR}
            if ($rest =~ /^(\$[\(\{])(\w+)([\)\}])/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_PUNCTUATION);
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_VARIABLE);
                $pos += length($2);
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
                next;
            }

            # Automatic variables $@ $< $^ etc.
            if ($rest =~ /^($AUTO_VARS)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
                $pos += length($1);
                next;
            }

            # Shell variables
            if ($rest =~ /^(\$\$[\w]+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
                $pos += length($1);
                next;
            }

            # String in recipe
            if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
                next;
            }

            $pos++;
        }

        return (\@tokens, STATE_NORMAL);
    }

    # Variable assignment: VAR = value, VAR := value, VAR ?= value, VAR += value
    if ($line =~ /^(\s*)(\w+)(\s*)([:?+]?=)/) {
        my $indent = $1;
        my $var = $2;
        my $space = $3;
        my $op = $4;

        $pos = length($indent);
        push @tokens, _token($pos, $pos + length($var), TOKEN_VARIABLE);
        $pos += length($var) + length($space);
        push @tokens, _token($pos, $pos + length($op), TOKEN_OPERATOR);
        $pos += length($op);

        # Rest is the value - highlight variables in it
        while ($pos < $len) {
            my $rest = substr($line, $pos);

            # Comment in assignment
            if ($rest =~ /^(\s*#.*)/) {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                last;
            }

            # Make variables
            if ($rest =~ /^(\$[\(\{])(\w+)([\)\}])/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_PUNCTUATION);
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_VARIABLE);
                $pos += length($2);
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
                next;
            }

            # Function calls
            if ($rest =~ /^(\$\()(subst|patsubst|strip|findstring|filter|filter-out|sort|word|wordlist|words|firstword|lastword|dir|notdir|suffix|basename|addsuffix|addprefix|join|wildcard|realpath|abspath|if|or|and|foreach|file|call|value|eval|origin|flavor|error|warning|info|shell)\b/) {
                push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
                $pos += 2;
                push @tokens, _token($pos, $pos + length($2), TOKEN_FUNCTION);
                $pos += length($2);
                next;
            }

            # Automatic variables
            if ($rest =~ /^($AUTO_VARS)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
                $pos += length($1);
                next;
            }

            $pos++;
        }

        return (\@tokens, STATE_NORMAL);
    }

    # Target: dependencies
    if ($line =~ /^([^:=]+)(:)(.*)/) {
        my $targets = $1;
        my $colon = $2;
        my $deps = $3;

        # Check for special targets
        if ($targets =~ /$SPECIAL_TARGETS/) {
            push @tokens, _token(0, length($targets), TOKEN_ATTRIBUTE);
        } else {
            push @tokens, _token(0, length($targets), TOKEN_FUNCTION);
        }

        $pos = length($targets);
        push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
        $pos += 1;

        # Highlight dependencies
        while ($pos < $len) {
            my $rest = substr($line, $pos);

            # Comment
            if ($rest =~ /^(\s*#.*)/) {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                last;
            }

            # Variables in dependencies
            if ($rest =~ /^(\$[\(\{])(\w+)([\)\}])/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_PUNCTUATION);
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_VARIABLE);
                $pos += length($2);
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
                next;
            }

            # Automatic variables
            if ($rest =~ /^($AUTO_VARS)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
                $pos += length($1);
                next;
            }

            $pos++;
        }

        return (\@tokens, STATE_NORMAL);
    }

    # Include directive
    if ($line =~ /^(\s*)(-?include)\s+(.*)/) {
        my $indent = $1;
        my $directive = $2;
        my $files = $3;

        $pos = length($indent);
        push @tokens, _token($pos, $pos + length($directive), TOKEN_KEYWORD);
        $pos += length($directive);

        # Rest is filenames - might contain variables
        while ($pos < $len) {
            my $rest = substr($line, $pos);

            if ($rest =~ /^(\$[\(\{])(\w+)([\)\}])/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_PUNCTUATION);
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_VARIABLE);
                $pos += length($2);
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
                next;
            }

            $pos++;
        }

        return (\@tokens, STATE_NORMAL);
    }

    # Conditional directives
    if ($line =~ /^(\s*)(ifeq|ifneq|ifdef|ifndef|else|endif)\b/) {
        my $indent = $1;
        my $directive = $2;
        $pos = length($indent);
        push @tokens, _token($pos, $pos + length($directive), TOKEN_KEYWORD);
        $pos += length($directive);

        # Continue parsing for variables
        while ($pos < $len) {
            my $rest = substr($line, $pos);

            if ($rest =~ /^(\$[\(\{])(\w+)([\)\}])/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_PUNCTUATION);
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_VARIABLE);
                $pos += length($2);
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
                next;
            }

            # Strings in conditionals
            if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
                next;
            }

            $pos++;
        }

        return (\@tokens, STATE_NORMAL);
    }

    # Export/unexport
    if ($line =~ /^(\s*)(export|unexport)\s+(\w+)/) {
        my $indent = $1;
        my $directive = $2;
        my $var = $3;

        $pos = length($indent);
        push @tokens, _token($pos, $pos + length($directive), TOKEN_KEYWORD);
        $pos += length($directive) + 1;
        push @tokens, _token($pos, $pos + length($var), TOKEN_VARIABLE);

        return (\@tokens, STATE_NORMAL);
    }

    # Default: just look for variables
    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\$[\(\{])(\w+)([\)\}])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_PUNCTUATION);
            $pos += length($1);
            push @tokens, _token($pos, $pos + length($2), TOKEN_VARIABLE);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        if ($rest =~ /^($AUTO_VARS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
