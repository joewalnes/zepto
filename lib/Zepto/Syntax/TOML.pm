package Zepto::Syntax::TOML;
# =============================================================================
# TOML Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue multi-line basic string
    if ($state == 10) {  # """..."""
        if ($line =~ /^(.*?)"""/) {
            push @tokens, _token(0, length($1) + 3, TOKEN_STRING);
            $pos = length($1) + 3;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, 10);
        }
    }

    # Continue multi-line literal string
    if ($state == 11) {  # '''...'''
        if ($line =~ /^(.*?)'''/) {
            push @tokens, _token(0, length($1) + 3, TOKEN_STRING);
            $pos = length($1) + 3;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, 11);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Comment
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Table header [[...]] (array of tables)
        if ($rest =~ /^(\[\[)([^\]]+)(\]\])/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            my $table_name = $2;
            push @tokens, _token($pos, $pos + length($table_name), TOKEN_TYPE);
            $pos += length($table_name);
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            next;
        }

        # Table header [...]
        if ($rest =~ /^(\[)([^\]]+)(\])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            my $table_name = $2;
            push @tokens, _token($pos, $pos + length($table_name), TOKEN_TYPE);
            $pos += length($table_name);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Multi-line basic string """..."""
        if ($rest =~ /^(""")/) {
            my $after_open = substr($rest, 3);
            if ($after_open =~ /^(.*?)"""/) {
                my $content_len = 3 + length($1) + 3;
                push @tokens, _token($pos, $pos + $content_len, TOKEN_STRING);
                $pos += $content_len;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, 10);
            }
            next;
        }

        # Multi-line literal string '''...'''
        if ($rest =~ /^(''')/) {
            my $after_open = substr($rest, 3);
            if ($after_open =~ /^(.*?)'''/) {
                my $content_len = 3 + length($1) + 3;
                push @tokens, _token($pos, $pos + $content_len, TOKEN_STRING);
                $pos += $content_len;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, 11);
            }
            next;
        }

        # Basic string "..."
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Literal string '...'
        if ($rest =~ /^('(?:[^'])*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Boolean
        if ($rest =~ /^(true|false)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Date/time (ISO 8601)
        if ($rest =~ /^(\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Time only
        if ($rest =~ /^(\d{2}:\d{2}:\d{2}(?:\.\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Numbers (integer, float, hex, octal, binary, inf, nan)
        if ($rest =~ /^([+-]?(?:inf|nan))\b/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^(0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|[+-]?\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Key (bare or dotted) before =
        if ($rest =~ /^([\w-]+(?:\.[\w-]+)*)(\s*=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            # Skip to = and mark it
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s*)(=)/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
                $pos += 1;
            }
            next;
        }

        # Operators
        if ($rest =~ /^([=,.\[\]{}])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
