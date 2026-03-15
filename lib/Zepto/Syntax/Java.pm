package Zepto::Syntax::Java;
# =============================================================================
# Java Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $KEYWORDS = qr/\b(?:
    abstract | assert | break | case | catch | class | const |
    continue | default | do | else | enum | extends | final |
    finally | for | goto | if | implements | import | instanceof |
    interface | native | new | package | private | protected |
    public | return | static | strictfp | super | switch |
    synchronized | this | throw | throws | transient | try |
    volatile | while | true | false | null
)\b/x;

my $PRIMITIVES = qr/\b(?:boolean|byte|char|double|float|int|long|short|void)\b/x;

my $COMMON_TYPES = qr/\b(?:
    String | Object | Class | System | Integer | Long | Double |
    Float | Boolean | Exception | RuntimeException | ArrayList |
    HashMap | List | Map | Set | Optional | Stream
)\b/x;

sub keyword_list {
    return [qw(
        abstract assert break case catch class const
        continue default do else enum extends final
        finally for goto if implements import instanceof
        interface native new package private protected
        public return static strictfp super switch
        synchronized this throw throws transient try
        volatile while true false null
        boolean byte char double float int long short void
        String Object Class System Integer Long Double
        Float Boolean Exception RuntimeException ArrayList
        HashMap List Map Set Optional Stream
    )];
}

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

        if ($rest =~ m{^(//.*)} ) {
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

        if ($rest =~ /^(@\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^('(?:[^'\\]|\\.)')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(package|import)\s+([\w.*]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:package|import)\s+([\w.*]+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        if ($rest =~ /^(class|interface|enum)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:class|interface|enum)\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^($PRIMITIVES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^($COMMON_TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(0x[0-9a-fA-F_]+[lL]?|0b[01_]+[lL]?|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?[fFdDlL]?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(->|::|==|!=|<=|>=|&&|\|\||<<|>>|[+\-*\/%&|^~<>=!])/) {
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

        if ($rest =~ /^([A-Z][a-zA-Z0-9_]*)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
