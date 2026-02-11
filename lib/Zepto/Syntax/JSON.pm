package Zepto::Syntax::JSON;
# =============================================================================
# JSON Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

# JSON keywords (literals)
my $LITERALS = qr/\b(true|false|null)\b/;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Skip whitespace
        if ($rest =~ /^(\s+)/) {
            $pos += length($1);
            next;
        }

        # Strings (double-quoted only in JSON)
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Keywords/literals
        if ($rest =~ /^($LITERALS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Numbers (JSON supports integers and floats with optional exponent)
        if ($rest =~ /^(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Punctuation (structural characters)
        if ($rest =~ /^([\[\]{}:,])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos++;
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
