package Zepto::Syntax::YAML;
# =============================================================================
# YAML Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub line_comment_prefix { '#' }

# YAML literals
my $LITERALS = qr/\b(true|false|null|yes|no|on|off|True|False|Null|Yes|No|On|Off|TRUE|FALSE|NULL|YES|NO|ON|OFF|~)\b/;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Empty line or whitespace only
    return (\@tokens, STATE_NORMAL) unless $len > 0;

    # Comment (entire line or from # onwards)
    if ($line =~ /^(\s*)(#.*)$/) {
        my $indent = length($1);
        push @tokens, _token($indent, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Document markers
    if ($line =~ /^(---|\.\.\.)/) {
        push @tokens, _token(0, length($1), TOKEN_KEYWORD);
        $pos = length($1);
    }

    # Directive (like %YAML or %TAG)
    if ($line =~ /^(%[A-Z]+)/) {
        push @tokens, _token(0, length($1), TOKEN_KEYWORD);
        $pos = length($1);
    }

    # Anchor and alias
    if ($line =~ /(&|\*)[a-zA-Z_][a-zA-Z0-9_]*/g) {
        # Will be handled in main loop
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Skip whitespace
        if ($rest =~ /^(\s+)/) {
            $pos += length($1);
            next;
        }

        # Comment
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Anchor (&name)
        if ($rest =~ /^(&[a-zA-Z_][a-zA-Z0-9_]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Alias (*name)
        if ($rest =~ /^(\*[a-zA-Z_][a-zA-Z0-9_]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Tag (like !!str, !custom)
        if ($rest =~ /^(!+[a-zA-Z0-9_-]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Key (word followed by colon)
        if ($rest =~ /^([a-zA-Z_][a-zA-Z0-9_-]*)\s*:/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Quoted key
        if ($rest =~ /^(['"][^'"]*['"])\s*:/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Double-quoted string
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Single-quoted string
        if ($rest =~ /^('(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Literals
        if ($rest =~ /^($LITERALS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(-?(?:0x[0-9a-fA-F]+|0o[0-7]+|0b[01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?))(?=\s|$|#|,|\]|\})/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Colon
        if ($rest =~ /^:/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos++;
            next;
        }

        # List/map markers
        if ($rest =~ /^([\[\]{},-])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos++;
            next;
        }

        # Block scalar indicators
        if ($rest =~ /^([|>][+-]?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Bare word — consume as a whole to avoid partial literal matches
        # (e.g. "region" contains "on" but should not be highlighted as a keyword)
        if ($rest =~ /^([a-zA-Z_][a-zA-Z0-9_.-]*)/) {
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
