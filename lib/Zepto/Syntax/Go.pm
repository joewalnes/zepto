package Zepto::Syntax::Go;
# =============================================================================
# Go Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

my $KEYWORDS = qr/\b(?:
    break | case | chan | const | continue | default | defer |
    else | fallthrough | for | func | go | goto | if | import |
    interface | map | package | range | return | select | struct |
    switch | type | var |
    true | false | nil | iota
)\b/x;

my $TYPES = qr/\b(?:
    bool | byte | complex64 | complex128 | error | float32 | float64 |
    int | int8 | int16 | int32 | int64 | rune | string |
    uint | uint8 | uint16 | uint32 | uint64 | uintptr | any | comparable
)\b/x;

my $BUILTINS = qr/\b(?:
    append | cap | close | complex | copy | delete | imag | len |
    make | new | panic | print | println | real | recover
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

    # Continue raw string
    if ($state == STATE_STRING_RAW) {
        if ($line =~ /^(.*?)`/) {
            push @tokens, _token(0, length($1) + 1, TOKEN_STRING);
            $pos = length($1) + 1;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_STRING_RAW);
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

        # Raw string literal
        if ($rest =~ /^`/) {
            if ($rest =~ /^(`[^`]*`)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_RAW);
            }
            next;
        }

        # Regular strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Rune literal
        if ($rest =~ /^('(?:[^'\\]|\\.)')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Package/import declaration
        if ($rest =~ /^(package|import)\s+/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # func declaration
        if ($rest =~ /^(func)\s+(?:\([^)]+\)\s*)?(\w+)/) {
            push @tokens, _token($pos, $pos + 4, TOKEN_KEYWORD);
            $pos += 4;
            while ($pos < $len && substr($line, $pos, 1) =~ /[\s(]/) {
                if (substr($line, $pos, 1) eq '(') {
                    # Skip receiver
                    my $depth = 1;
                    $pos++;
                    while ($pos < $len && $depth > 0) {
                        $depth++ if substr($line, $pos, 1) eq '(';
                        $depth-- if substr($line, $pos, 1) eq ')';
                        $pos++;
                    }
                } else {
                    $pos++;
                }
            }
            if ($rest =~ /^func\s+(?:\([^)]+\)\s*)?(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        # type declaration
        if ($rest =~ /^(type)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 4, TOKEN_KEYWORD);
            $pos += 4;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^type\s+(\w+)/) {
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
        if ($rest =~ /^($BUILTINS)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?i?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(:=|<-|&&|\|\||<<|>>|&\^|[+\-*\/%&|^<>=!]=?|\.\.\.?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Function call
        if ($rest =~ /^(\w+)(?=\s*\()/) {
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

        # PascalCase type
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
