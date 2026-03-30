package Zepto::Syntax::Python;
# =============================================================================
# Python Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '#' }

sub keyword_list {
    return [qw(
        and as assert async await break class continue
        def del elif else except finally for from
        global if import in is lambda nonlocal not
        or pass raise return try while with yield
        True False None
        abs aiter all any anext ascii bin bool breakpoint
        bytearray bytes callable chr classmethod compile complex
        delattr dict dir divmod enumerate eval exec filter
        float format frozenset getattr globals hasattr hash help
        hex id input int isinstance issubclass iter len list
        locals map max memoryview min next object oct open
        ord pow print property range repr reversed round set
        setattr slice sorted staticmethod str sum super tuple
        type vars zip __import__
        BaseException Exception ArithmeticError AssertionError
        AttributeError EOFError ImportError IndexError KeyError
        MemoryError NameError OSError RuntimeError StopIteration
        SyntaxError TypeError ValueError ZeroDivisionError
    )];
}

my $KEYWORDS = qr/\b(?:
    and | as | assert | async | await | break | class | continue |
    def | del | elif | else | except | finally | for | from |
    global | if | import | in | is | lambda | nonlocal | not |
    or | pass | raise | return | try | while | with | yield |
    True | False | None
)\b/x;

my $BUILTINS = qr/\b(?:
    abs | aiter | all | any | anext | ascii | bin | bool | breakpoint |
    bytearray | bytes | callable | chr | classmethod | compile | complex |
    delattr | dict | dir | divmod | enumerate | eval | exec | filter |
    float | format | frozenset | getattr | globals | hasattr | hash | help |
    hex | id | input | int | isinstance | issubclass | iter | len | list |
    locals | map | max | memoryview | min | next | object | oct | open |
    ord | pow | print | property | range | repr | reversed | round | set |
    setattr | slice | sorted | staticmethod | str | sum | super | tuple |
    type | vars | zip | __import__
)\b/x;

my $EXCEPTIONS = qr/\b(?:
    BaseException | Exception | ArithmeticError | AssertionError |
    AttributeError | EOFError | ImportError | IndexError | KeyError |
    MemoryError | NameError | OSError | RuntimeError | StopIteration |
    SyntaxError | TypeError | ValueError | ZeroDivisionError
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue PEP 723 inline script metadata (# /// script ... # ///)
    if ($state == 12) {
        # Closing delimiter
        if ($line =~ /^(\s*#\s*\/\/\/)$/) {
            push @tokens, _token(0, $len, TOKEN_HEADING);
            return (\@tokens, STATE_NORMAL);
        }
        # Content line — highlight # prefix, then parse TOML innards
        if ($line =~ /^(\s*#)(.*)/) {
            my $prefix_len = length($1);
            push @tokens, _token(0, $prefix_len, TOKEN_ATTRIBUTE);
            my $toml = $2;
            my $tpos = $prefix_len;
            my $tlen = $len;
            while ($tpos < $tlen) {
                my $trest = substr($line, $tpos);

                if ($trest =~ /^(\s+)/) { $tpos += length($1); next; }

                # Strings
                if ($trest =~ /^("(?:[^"\\]|\\.)*")/) {
                    push @tokens, _token($tpos, $tpos + length($1), TOKEN_STRING);
                    $tpos += length($1);
                    next;
                }
                if ($trest =~ /^('(?:[^'])*')/) {
                    push @tokens, _token($tpos, $tpos + length($1), TOKEN_STRING);
                    $tpos += length($1);
                    next;
                }

                # Booleans
                if ($trest =~ /^(true|false)\b/) {
                    push @tokens, _token($tpos, $tpos + length($1), TOKEN_KEYWORD);
                    $tpos += length($1);
                    next;
                }

                # Numbers
                if ($trest =~ /^(\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?)/) {
                    push @tokens, _token($tpos, $tpos + length($1), TOKEN_NUMBER);
                    $tpos += length($1);
                    next;
                }

                # Key before =
                if ($trest =~ /^([\w-]+(?:\.[\w-]+)*)(\s*=)/) {
                    push @tokens, _token($tpos, $tpos + length($1), TOKEN_VARIABLE);
                    $tpos += length($1);
                    $trest = substr($line, $tpos);
                    if ($trest =~ /^(\s*)(=)/) {
                        $tpos += length($1);
                        push @tokens, _token($tpos, $tpos + 1, TOKEN_OPERATOR);
                        $tpos += 1;
                    }
                    next;
                }

                # Brackets and commas
                if ($trest =~ /^([\[\],])/) {
                    push @tokens, _token($tpos, $tpos + 1, TOKEN_PUNCTUATION);
                    $tpos += 1;
                    next;
                }

                $tpos++;
            }
            return (\@tokens, 12);
        }
        # Non-comment line ends the block (malformed, but recover)
        $state = STATE_NORMAL;
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
    if ($state == 11) {
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

        # PEP 723 inline script metadata: # /// script
        if ($pos == 0 && $line =~ /^(\s*#\s*\/\/\/\s+script\s*)$/) {
            push @tokens, _token(0, $len, TOKEN_HEADING);
            return (\@tokens, 12);
        }

        # Comment
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Decorator
        if ($rest =~ /^(@[\w.]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Triple-quoted strings
        if ($rest =~ /^([fFrRbBuU]?)("""|''')/) {
            my $prefix = $1;
            my $delim = $2;
            my $pattern = quotemeta($delim);
            my $after_open = substr($rest, length($prefix) + 3);
            if ($after_open =~ /^(.*?)$pattern/) {
                my $content_len = length($prefix) + 3 + length($1) + 3;
                push @tokens, _token($pos, $pos + $content_len, TOKEN_STRING);
                $pos += $content_len;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, $delim eq '"""' ? 10 : 11);
            }
            next;
        }

        # Regular strings
        if ($rest =~ /^([fFrRbBuU]*)("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1) + length($2), TOKEN_STRING);
            $pos += length($1) + length($2);
            next;
        }

        # def/class
        if ($rest =~ /^(def)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 3, TOKEN_KEYWORD);
            $pos += 3;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^def\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }
        if ($rest =~ /^(class)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 5, TOKEN_KEYWORD);
            $pos += 5;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^class\s+(\w+)/) {
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

        if ($rest =~ /^($BUILTINS)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^($EXCEPTIONS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(self|cls)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?j?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(->|:=|==|!=|<=|>=|\*\*|\/\/|[+\-*\/%&|^~<>=@])/) {
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
