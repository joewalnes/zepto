package Zepto::Syntax::Kotlin;
# =============================================================================
# Kotlin Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $KEYWORDS = qr/\b(?:
    abstract | actual | annotation | as | break | by | catch | class |
    companion | const | constructor | continue | crossinline | data | do |
    else | enum | expect | external | false | final | finally | for | fun |
    get | if | import | in | infix | init | inline | inner | interface |
    internal | is | lateinit | noinline | null | object | open | operator |
    out | override | package | private | protected | public | reified |
    return | sealed | set | super | suspend | tailrec | this | throw | true |
    try | typealias | typeof | val | var | vararg | when | where | while
)\b/x;

my $TYPES = qr/\b(?:
    Any | Boolean | Byte | Char | Double | Float | Int | Long | Nothing |
    Number | Short | String | Unit |
    Array | List | Map | Set | MutableList | MutableMap | MutableSet |
    Pair | Triple | Sequence | Iterable | Collection |
    Comparable | Throwable | Exception | Error | Result
)\b/x;

my $BUILTINS = qr/\b(?:
    println | print | readLine | require | requireNotNull | check |
    checkNotNull | error | assert | TODO | run | let | also | apply |
    with | takeIf | takeUnless | repeat | lazy | synchronized |
    listOf | mutableListOf | arrayListOf | setOf | mutableSetOf |
    hashSetOf | linkedSetOf | sortedSetOf | mapOf | mutableMapOf |
    hashMapOf | linkedMapOf | sortedMapOf | arrayOf | intArrayOf |
    longArrayOf | shortArrayOf | byteArrayOf | charArrayOf |
    booleanArrayOf | floatArrayOf | doubleArrayOf | emptyList |
    emptySet | emptyMap | sequenceOf | generateSequence | to | until |
    downTo | step | rangeTo
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

    # Continue multiline string
    if ($state == 10) {  # Triple-quoted string
        if ($line =~ /^(.*?)"""/) {
            push @tokens, _token(0, length($1) + 3, TOKEN_STRING);
            $pos = length($1) + 3;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, 10);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line comment
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

        # Annotation
        if ($rest =~ /^(@\w+(?:\.\w+)*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Triple-quoted string (raw string)
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

        # Regular strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Character literal
        if ($rest =~ /^('(?:[^'\\]|\\.)')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # fun declaration
        if ($rest =~ /^(fun)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 3, TOKEN_KEYWORD);
            $pos += 3;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^fun\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        # class/interface/object/enum declaration
        if ($rest =~ /^(class|interface|object|enum)\s+(\w+)/) {
            my $kw = $1;
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:class|interface|object|enum)\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Built-in types
        if ($rest =~ /^($TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Built-in functions
        if ($rest =~ /^($BUILTINS)(?=\s*[({<])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers (including underscores and suffixes)
        if ($rest =~ /^(0x[0-9a-fA-F_]+[uUlL]*|0b[01_]+[uUlL]*|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?[fFlL]?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(===|!==|->|::|\.\.|\?\.|!!|\+\+|--|&&|\|\||[+\-*\/%&|^<>=!]=?|<<?|>>?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Function call or type with generics
        if ($rest =~ /^(\w+)(?=\s*[<(])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # CONSTANT_NAME
        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Type name (PascalCase)
        if ($rest =~ /^([A-Z][a-zA-Z0-9]*)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
