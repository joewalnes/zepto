package Zepto::Syntax::PHP;
# =============================================================================
# PHP Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

my $KEYWORDS = qr/\b(?:
    abstract | and | array | as | break | callable | case | catch |
    class | clone | const | continue | declare | default | die |
    do | echo | else | elseif | empty | enddeclare | endfor |
    endforeach | endif | endswitch | endwhile | eval | exit |
    extends | final | finally | fn | for | foreach | function |
    global | goto | if | implements | include | include_once |
    instanceof | insteadof | interface | isset | list | match |
    namespace | new | or | print | private | protected | public |
    readonly | require | require_once | return | static | switch |
    throw | trait | try | unset | use | var | while | xor | yield |
    true | false | null |
    __CLASS__ | __DIR__ | __FILE__ | __FUNCTION__ | __LINE__ |
    __METHOD__ | __NAMESPACE__ | __TRAIT__
)\b/xi;

my $BUILTINS = qr/\b(?:
    array_map | array_merge | array_keys | array_values | count |
    echo | empty | explode | implode | in_array | isset | json_decode |
    json_encode | print_r | sprintf | strlen | strpos | substr | trim
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

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

        if ($rest =~ /^(<\?(?:php)?|\?>)/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TAG);
            $pos += length($1);
            next;
        }

        if ($rest =~ m{^(//.*|#[^\[].*)} ) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        if ($rest =~ m{^(/\*\*?)}) {
            if ($rest =~ m{^(/\*\*?.*?\*/)}) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_COMMENT_BLOCK);
            }
            next;
        }

        if ($rest =~ /^(#\[[\w\\]+(?:\([^)]*\))?\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(namespace|class|interface|trait|enum)\s+([\w\\]+)/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:namespace|class|interface|trait|enum)\s+([\w\\]+)/i) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        if ($rest =~ /^(function)\s+(\w+)/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^function\s+(\w+)/i) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        if ($rest =~ /^($KEYWORDS)/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^($BUILTINS)(?=\s*\()/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\$\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(0x[0-9a-fA-F_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(=>|->|\?->|::|<=>|\?\?|===|!==|==|!=|<=|>=|&&|\|\||[+\-*\/%&|^~<>=!.@])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\w+)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\\?[A-Z][a-zA-Z0-9_]*(?:\\[A-Z][a-zA-Z0-9_]*)*)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
