package Zepto::Syntax::GraphQL;
# =============================================================================
# GraphQL Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

use constant STATE_BLOCK_STRING => 10;

my $KEYWORDS = qr/\b(?:
    query | mutation | subscription | fragment | on | type | interface |
    union | enum | input | scalar | extend | implements | directive |
    schema | repeatable
)\b/x;

my $BUILTIN_TYPES = qr/\b(?:
    String | Int | Float | Boolean | ID
)\b/x;

my $CONSTANTS = qr/\b(?:
    true | false | null
)\b/x;

my $DIRECTIVES_RE = qr/\@(?:
    deprecated | skip | include | specifiedBy | oneOf |
    cacheControl | tag | inaccessible | shareable | override |
    external | provides | requires | key | extends
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue block string """..."""
    if ($state == STATE_BLOCK_STRING) {
        if ($line =~ /^(.*?)"""/) {
            push @tokens, _token(0, length($1) + 3, TOKEN_STRING);
            $pos = length($1) + 3;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_BLOCK_STRING);
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

        # Block string """..."""
        if ($rest =~ /^(""")/) {
            if ($rest =~ /^("""(?:(?!""")[\s\S])*""")/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_BLOCK_STRING);
            }
            next;
        }

        # String
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Directives (@deprecated, @skip, etc.)
        if ($rest =~ /^(\@\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Variables $var
        if ($rest =~ /^(\$\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Spread operator ...
        if ($rest =~ /^(\.\.\.)/) {
            push @tokens, _token($pos, $pos + 3, TOKEN_OPERATOR);
            $pos += 3;
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Built-in scalar types
        if ($rest =~ /^($BUILTIN_TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Constants
        if ($rest =~ /^($CONSTANTS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(-?\d+\.?\d*(?:e[+-]?\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Type names (PascalCase)
        if ($rest =~ /^([A-Z]\w*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Field names followed by arguments or colon
        if ($rest =~ /^(\w+)(?=\s*[\(:{])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Punctuation
        if ($rest =~ /^([{}()\[\]:!=|&])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Operators
        if ($rest =~ /^(=)/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, $state);
}

1;
