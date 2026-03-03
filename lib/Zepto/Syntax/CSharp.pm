package Zepto::Syntax::CSharp;
# =============================================================================
# C# Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $KEYWORDS = qr/\b(?:
    abstract | as | base | bool | break | byte | case | catch | char |
    checked | class | const | continue | decimal | default | delegate |
    do | double | else | enum | event | explicit | extern | false |
    finally | fixed | float | for | foreach | goto | if | implicit |
    in | int | interface | internal | is | lock | long | namespace |
    new | null | object | operator | out | override | params | private |
    protected | public | readonly | ref | return | sbyte | sealed |
    short | sizeof | stackalloc | static | string | struct | switch |
    this | throw | true | try | typeof | uint | ulong | unchecked |
    unsafe | ushort | using | virtual | void | volatile | while |
    add | alias | ascending | async | await | by | descending | dynamic |
    equals | from | get | global | group | into | join | let | nameof |
    on | orderby | partial | remove | select | set | value | var |
    when | where | with | yield | init | record | required | file |
    managed | unmanaged | notnull | nint | nuint | and | or | not
)\b/x;

my $TYPES = qr/\b(?:
    bool | byte | sbyte | char | decimal | double | float | int | uint |
    long | ulong | short | ushort | object | string | dynamic | void |
    nint | nuint |
    Boolean | Byte | SByte | Char | Decimal | Double | Single | Int16 |
    Int32 | Int64 | UInt16 | UInt32 | UInt64 | Object | String |
    Array | List | Dictionary | HashSet | Queue | Stack | LinkedList |
    Tuple | ValueTuple | Nullable | Task | Action | Func | Predicate |
    IEnumerable | IEnumerator | IList | IDictionary | ICollection |
    IComparable | IDisposable | IEquatable | ICloneable | EventHandler |
    Exception | ArgumentException | InvalidOperationException |
    NullReferenceException | IndexOutOfRangeException
)\b/x;

my $BUILTINS = qr/\b(?:
    Console | Math | Convert | Enum | DateTime | TimeSpan | Guid |
    Environment | File | Directory | Path | Stream | StreamReader |
    StreamWriter | StringBuilder | Regex | Thread | Task | Parallel |
    Enumerable | Queryable | GC | Debug | Trace | Assert
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

    # Continue verbatim string
    if ($state == 10) {  # @"..." string
        if ($line =~ /^((?:[^"]|"")*)"/) {
            push @tokens, _token(0, length($1) + 1, TOKEN_STRING);
            $pos = length($1) + 1;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, 10);
        }
    }

    # Continue raw string literal
    if ($state == 11) {  # """...""" string
        if ($line =~ /^(.*?)"""/) {
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

        # Preprocessor directive
        if ($pos == 0 && $rest =~ /^(\s*#\s*(?:if|elif|else|endif|define|undef|warning|error|line|region|endregion|pragma|nullable).*)/) {
            push @tokens, _token(0, length($1), TOKEN_KEYWORD);
            last;
        }

        # Attribute
        if ($rest =~ /^(\[[\w.]+(?:\([^)]*\))?\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Raw string literal (C# 11+) """..."""
        if ($rest =~ /^(""")/) {
            my $after_open = substr($rest, 3);
            if ($after_open =~ /^(.*?)"""/) {
                my $content_len = 3 + length($1) + 3;
                push @tokens, _token($pos, $pos + $content_len, TOKEN_STRING);
                $pos += $content_len;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, 11);
            }
            next;
        }

        # Verbatim string @"..."
        if ($rest =~ /^(@"(?:[^"]|"")*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^(@")/) {
            push @tokens, _token($pos, $len, TOKEN_STRING);
            return (\@tokens, 10);
        }

        # Interpolated string $"..."
        if ($rest =~ /^(\$"(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Verbatim interpolated string $@"..." or @$"..."
        if ($rest =~ /^((?:\$@|@\$)"(?:[^"]|"")*")/) {
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

        # class/struct/interface/enum/record declaration
        if ($rest =~ /^(class|struct|interface|enum|record)\s+(\w+)/) {
            my $kw = $1;
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:class|struct|interface|enum|record)\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        # namespace declaration
        if ($rest =~ /^(namespace)\s+([\w.]+)/) {
            push @tokens, _token($pos, $pos + 9, TOKEN_KEYWORD);
            $pos += 9;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^namespace\s+([\w.]+)/) {
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

        # Built-in classes
        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F_]+[uUlL]*|0b[01_]+[uUlL]*|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?[fFdDmMuUlL]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(=>|->|\?\?=|\?\?|\?\.|\?\[|::|\.\.|\+\+|--|&&|\|\||[+\-*\/%&|^<>=!]=?|<<?=?|>>?=?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Method call or generic type
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
