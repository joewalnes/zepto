package Zepto::Syntax::Scala;
# =============================================================================
# Scala Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

my $KEYWORDS = qr/\b(?:
    abstract | case | catch | class | def | do | else | enum | export |
    extends | false | final | finally | for | forSome | given | if |
    implicit | import | lazy | match | new | null | object | override |
    package | private | protected | return | sealed | super | then |
    this | throw | trait | true | try | type | using | val | var |
    while | with | yield |
    inline | opaque | open | transparent | derives | end | extension |
    infix | erased
)\b/x;

my $TYPES = qr/\b(?:
    Any | AnyRef | AnyVal | Boolean | Byte | Char | Double | Float |
    Int | Long | Nothing | Null | Short | String | Unit |
    Array | List | Map | Set | Seq | Vector | Option | Some | None |
    Either | Left | Right | Try | Success | Failure | Future |
    Tuple | Range | Stream | LazyList | Iterator | Iterable |
    Collection | Traversable | IndexedSeq | LinearSeq | Buffer |
    StringBuilder | BigInt | BigDecimal
)\b/x;

my $BUILTINS = qr/\b(?:
    println | print | printf | readLine | require | assert |
    classOf | isInstanceOf | asInstanceOf | hashCode | equals | toString |
    apply | unapply | update | copy | canEqual | productArity |
    productElement | productIterator | productPrefix |
    map | flatMap | filter | filterNot | foreach | fold | foldLeft |
    foldRight | reduce | reduceLeft | reduceRight | collect | find |
    exists | forall | contains | count | head | tail | last | init |
    take | drop | takeWhile | dropWhile | slice | splitAt | span |
    partition | groupBy | zip | zipWithIndex | unzip | flatten |
    distinct | sorted | sortBy | sortWith | reverse | mkString |
    toList | toArray | toSet | toMap | toVector | toSeq | toIndexedSeq |
    getOrElse | orElse | isDefined | isEmpty | nonEmpty | size | length
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

    # Continue triple-quoted string
    if ($state == 10) {
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

        # Interpolated string s"...", f"...", raw"..."
        if ($rest =~ /^([sfrS]"(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Regular strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
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

        # Symbol 'name
        if ($rest =~ /^('[\w]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # def declaration
        if ($rest =~ /^(def)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 3, TOKEN_KEYWORD);
            $pos += 3;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        # class/trait/object/enum declaration
        if ($rest =~ /^(class|trait|object|enum|type)\s+(\w+)/) {
            my $kw = $1;
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^(\w+)/) {
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

        # Built-in functions (when followed by parens or dot)
        if ($rest =~ /^($BUILTINS)(?=\s*[.(])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F_]+[lL]?|0b[01_]+[lL]?|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?[fFdDlL]?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(=>|->|<-|::|<:|>:|<%|=:=|=!=|##|\+\+|--|&&|\|\||[+\-*\/%&|^~<>=!:]=?|@)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Function call or type with generics
        if ($rest =~ /^(\w+)(?=\s*[\[(])/) {
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
