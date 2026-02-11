package Zepto::Syntax::C;
# =============================================================================
# C Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

my $KEYWORDS = qr/\b(?:
    auto | break | case | const | continue | default | do | else |
    enum | extern | for | goto | if | inline | register | restrict |
    return | sizeof | static | struct | switch | typedef | union |
    volatile | while |
    _Alignas | _Alignof | _Atomic | _Bool | _Complex | _Generic |
    _Imaginary | _Noreturn | _Static_assert | _Thread_local |
    alignas | alignof | bool | complex | imaginary | noreturn |
    static_assert | thread_local | true | false | NULL
)\b/x;

my $TYPES = qr/\b(?:
    void | char | short | int | long | float | double | signed | unsigned |
    int8_t | int16_t | int32_t | int64_t |
    uint8_t | uint16_t | uint32_t | uint64_t |
    size_t | ssize_t | ptrdiff_t | intptr_t | uintptr_t |
    FILE | va_list | wchar_t | wint_t
)\b/x;

my $BUILTINS = qr/\b(?:
    printf | fprintf | sprintf | snprintf | scanf | fscanf | sscanf |
    malloc | calloc | realloc | free |
    memcpy | memmove | memset | memcmp |
    strcpy | strncpy | strcat | strncat | strcmp | strncmp | strlen |
    fopen | fclose | fread | fwrite | fgets | fputs | fseek | ftell |
    exit | abort | assert | perror
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

        # Preprocessor directive
        if ($pos == 0 && $rest =~ /^(\s*#\s*\w+)/) {
            # Match the directive keyword
            push @tokens, _token(0, length($1), TOKEN_KEYWORD);
            $pos = length($1);

            # Continue parsing for includes, defines, etc.
            $rest = substr($line, $pos);

            # #include <...> or "..."
            if ($rest =~ /^(\s*)(<[^>]+>|"[^"]+")/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_STRING);
                $pos += length($2);
            }
            next;
        }

        # Line comment (C99+)
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

        # String literal
        if ($rest =~ /^(L?"(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Character literal
        if ($rest =~ /^(L?'(?:[^'\\]|\\.)')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # struct/enum/union declaration
        if ($rest =~ /^(struct|enum|union)\s+(\w+)/) {
            my $kw = $1;
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:struct|enum|union)\s+(\w+)/) {
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
        if ($rest =~ /^(0x[0-9a-fA-F]+[uUlL]*|0b[01]+[uUlL]*|\d+\.?\d*(?:e[+-]?\d+)?[fFlLuU]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(->|<<|>>|\+\+|--|&&|\|\||[+\-*\/%&|^<>=!]=?|::)/) {
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

        # CONSTANT_NAME or macro
        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Type name (PascalCase or ending in _t)
        if ($rest =~ /^([A-Z][a-zA-Z0-9]*|[a-z][a-zA-Z0-9]*_t)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
