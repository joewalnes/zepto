package Zepto::Syntax::SCSS;
# =============================================================================
# SCSS/Sass/Less Syntax Grammar
# =============================================================================
# Handles SCSS (.scss), Sass (.sass), and Less (.less) CSS preprocessor syntax

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $AT_RULES = qr/\@(?:
    import | use | forward | mixin | include | extend | function | return |
    if | else | each | for | while | debug | warn | error |
    at-root | content | charset | namespace | supports | layer |
    media | keyframes | font-face | page | viewport | container |
    plugin | apply | screen | responsive | tailwind
)\b/x;

my $CSS_PROPERTIES = qr/\b(?:
    display | position | float | clear | overflow | visibility |
    width | height | min-width | max-width | min-height | max-height |
    margin | margin-top | margin-right | margin-bottom | margin-left |
    padding | padding-top | padding-right | padding-bottom | padding-left |
    border | border-width | border-style | border-color | border-radius |
    background | background-color | background-image | background-size |
    color | font | font-size | font-weight | font-family | font-style |
    text-align | text-decoration | text-transform | line-height |
    letter-spacing | word-spacing | white-space | vertical-align |
    top | right | bottom | left | z-index | opacity |
    flex | flex-direction | flex-wrap | justify-content | align-items | align-self |
    grid | grid-template | grid-template-columns | grid-template-rows | gap |
    transition | transform | animation | box-shadow | cursor | content |
    list-style | outline | box-sizing | pointer-events | user-select
)\b/x;

my $VALUE_KEYWORDS = qr/\b(?:
    inherit | initial | unset | revert | none | auto | normal |
    bold | italic | underline | block | inline | inline-block | flex | grid |
    absolute | relative | fixed | sticky | hidden | visible | scroll |
    center | left | right | top | bottom |
    solid | dashed | dotted | transparent | currentColor |
    ease | linear | ease-in | ease-out | ease-in-out |
    infinite | alternate | forwards | backwards | both |
    important | default | global | null
)\b/x;

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

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Single-line comment //
        if ($rest =~ m{^(//.*)} ) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Block comment
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

        # At-rules (@mixin, @include, @if, etc.)
        if ($rest =~ /^($AT_RULES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Variables: $var (SCSS) or @var (Less)
        if ($rest =~ /^(\$[\w-]+|\@[\w-]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Interpolation #{$var}
        if ($rest =~ /^(#\{[^}]*\})/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Mixin/function call with arguments
        if ($rest =~ /^(\@include\s+)([\w-]+)/) {
            push @tokens, _token($pos, $pos + length($1) - 1, TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^([\w-]+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        # Strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Class selectors
        if ($rest =~ /^(\.[a-zA-Z_][\w-]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # ID selectors
        if ($rest =~ /^(#[a-zA-Z_][\w-]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Pseudo-classes/elements
        if ($rest =~ /^(::?[\w-]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # & parent selector
        if ($rest =~ /^(&)/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_KEYWORD);
            $pos += 1;
            next;
        }

        # Property names (word-chars and hyphens before colon)
        if ($rest =~ /^($CSS_PROPERTIES)\s*:/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # !important and !default
        if ($rest =~ /^(!\s*(?:important|default|global|optional))/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
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

        # Functions
        if ($rest =~ /^([\w-]+)\s*\(/) {
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

        # Operators
        if ($rest =~ /^(\+|-|\*|\/|%|==|!=|>=|<=|>|<|=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Punctuation
        if ($rest =~ /^([{}();:,])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, $state);
}

1;
