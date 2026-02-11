package Zepto::Syntax::CSS;
# =============================================================================
# CSS Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

# CSS at-rules
my $AT_RULES = qr/\@(import|media|keyframes|font-face|supports|charset|namespace|page|viewport|counter-style|layer|container|property|scope)\b/;

# CSS pseudo-classes and pseudo-elements
my $PSEUDO = qr/:(hover|active|focus|visited|first-child|last-child|nth-child|before|after|not|root|empty|target|enabled|disabled|checked|first-of-type|last-of-type|only-child|only-of-type|nth-of-type|nth-last-child|nth-last-of-type|focus-within|focus-visible|is|where|has)\b/;

# CSS property values that are keywords
my $VALUE_KEYWORDS = qr/\b(inherit|initial|unset|revert|none|auto|normal|bold|italic|underline|block|inline|flex|grid|absolute|relative|fixed|sticky|hidden|visible|scroll|center|left|right|top|bottom|solid|dashed|dotted|transparent|currentColor|ease|linear|ease-in|ease-out|ease-in-out|infinite|alternate|forwards|backwards|both|running|paused)\b/;

# CSS units
my $UNITS = qr/\b(\d+(?:\.\d+)?)(px|em|rem|%|vh|vw|vmin|vmax|ch|ex|pt|pc|in|cm|mm|deg|rad|turn|s|ms|fr)\b/;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue block comment
    if ($state == STATE_COMMENT_BLOCK) {
        if ($line =~ /^(.*?)\*\//) {
            push @tokens, _token(0, length($1) + 2, TOKEN_COMMENT);
            $pos = length($1) + 2;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_COMMENT_BLOCK);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Skip whitespace
        if ($rest =~ /^(\s+)/) {
            $pos += length($1);
            next;
        }

        # Block comment start
        if ($rest =~ m{^(/\*)}) {
            if ($rest =~ m{^(/\*.*?\*/)}) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_COMMENT_BLOCK);
            }
            next;
        }

        # At-rules
        if ($rest =~ /^($AT_RULES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Selectors: element names, classes, IDs
        if ($rest =~ /^(\.[a-zA-Z_][\w-]*)/) {
            # Class selector
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(#[a-zA-Z_][\w-]*)/) {
            # ID selector
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Pseudo-classes and pseudo-elements
        if ($rest =~ /^(::?[a-zA-Z-]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Property names (followed by colon)
        if ($rest =~ /^([a-zA-Z-]+)\s*:/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Numbers with units
        if ($rest =~ /^(\d+(?:\.\d+)?)(px|em|rem|%|vh|vw|vmin|vmax|ch|ex|pt|pc|in|cm|mm|deg|rad|turn|s|ms|fr)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            push @tokens, _token($pos, $pos + length($2), TOKEN_KEYWORD);
            $pos += length($2);
            next;
        }

        # Plain numbers
        if ($rest =~ /^(\d+(?:\.\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Color hex values
        if ($rest =~ /^(#[0-9a-fA-F]{3,8})\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Functions (like rgb(), url(), calc())
        if ($rest =~ /^([a-zA-Z-]+)\s*\(/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Value keywords
        if ($rest =~ /^($VALUE_KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Punctuation
        if ($rest =~ /^([{}();:,])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos++;
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
