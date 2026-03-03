package Zepto::Syntax::Cpp;
# =============================================================================
# C++ Syntax Grammar (extends C)
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

# C++ keywords (includes C keywords plus C++ specific)
my $KEYWORDS = qr/\b(?:
    alignas | alignof | and | and_eq | asm | auto | bitand | bitor |
    bool | break | case | catch | char | char8_t | char16_t | char32_t |
    class | compl | concept | const | consteval | constexpr | constinit |
    const_cast | continue | co_await | co_return | co_yield |
    decltype | default | delete | do | double | dynamic_cast |
    else | enum | explicit | export | extern | false | float | for |
    friend | goto | if | inline | int | long | mutable | namespace |
    new | noexcept | not | not_eq | nullptr | operator | or | or_eq |
    private | protected | public | register | reinterpret_cast |
    requires | return | short | signed | sizeof | static | static_assert |
    static_cast | struct | switch | template | this | thread_local |
    throw | true | try | typedef | typeid | typename | union | unsigned |
    using | virtual | void | volatile | wchar_t | while | xor | xor_eq |
    NULL | override | final
)\b/x;

my $TYPES = qr/\b(?:
    void | char | short | int | long | float | double | signed | unsigned |
    bool | wchar_t | char8_t | char16_t | char32_t | auto |
    int8_t | int16_t | int32_t | int64_t |
    uint8_t | uint16_t | uint32_t | uint64_t |
    size_t | ssize_t | ptrdiff_t | intptr_t | uintptr_t |
    string | wstring | string_view |
    vector | list | deque | array | forward_list |
    set | multiset | map | multimap |
    unordered_set | unordered_multiset | unordered_map | unordered_multimap |
    stack | queue | priority_queue |
    pair | tuple | optional | variant | any |
    unique_ptr | shared_ptr | weak_ptr |
    function | bind | reference_wrapper |
    thread | mutex | condition_variable | future | promise |
    istream | ostream | iostream | ifstream | ofstream | fstream |
    stringstream | istringstream | ostringstream
)\b/x;

my $BUILTINS = qr/\b(?:
    std | cout | cerr | cin | endl | flush |
    printf | fprintf | sprintf | snprintf | scanf |
    malloc | calloc | realloc | free |
    new | delete |
    memcpy | memmove | memset | memcmp |
    strcpy | strncpy | strcat | strcmp | strlen |
    move | forward | swap | make_unique | make_shared |
    begin | end | size | empty | front | back | push_back | pop_back |
    static_cast | dynamic_cast | const_cast | reinterpret_cast
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
        # Raw strings end with )delimiter"
        if ($line =~ /\)"/) {
            my $end_pos = $+[0];
            push @tokens, _token(0, $end_pos, TOKEN_STRING);
            $pos = $end_pos;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_STRING_RAW);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Preprocessor directive
        if ($pos == 0 && $rest =~ /^(\s*#\s*\w+)/) {
            push @tokens, _token(0, length($1), TOKEN_KEYWORD);
            $pos = length($1);
            $rest = substr($line, $pos);

            # #include <...> or "..."
            if ($rest =~ /^(\s*)(<[^>]+>|"[^"]+")/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_STRING);
                $pos += length($2);
            }
            next;
        }

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

        # Raw string literal R"delimiter(...)delimiter"
        if ($rest =~ /^(R"(\w*)\()/) {
            my $prefix = $1;
            my $delim = $2;
            my $pattern = ')' . $delim . '"';
            my $end_idx = index($rest, $pattern, length($prefix));
            if ($end_idx >= 0) {
                my $full_len = $end_idx + length($pattern);
                push @tokens, _token($pos, $pos + $full_len, TOKEN_STRING);
                $pos += $full_len;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_RAW);
            }
            next;
        }

        # String literal
        if ($rest =~ /^((?:u8|u|U|L)?"(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Character literal
        if ($rest =~ /^((?:u8|u|U|L)?'(?:[^'\\]|\\.)')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # class/struct/enum/namespace declaration
        if ($rest =~ /^(class|struct|enum|namespace|concept)\s+(\w+)/) {
            my $kw = $1;
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:class|struct|enum|namespace|concept)\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        # template declaration
        if ($rest =~ /^(template)\s*</) {
            push @tokens, _token($pos, $pos + 8, TOKEN_KEYWORD);
            $pos += 8;
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # STL and built-in types (check std:: prefix)
        if ($rest =~ /^(std::)(\w+)/) {
            push @tokens, _token($pos, $pos + 5, TOKEN_TYPE);
            $pos += 5;
            next;
        }

        # Built-in types
        if ($rest =~ /^($TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Numbers (including user-defined literals)
        if ($rest =~ /^(0x[0-9a-fA-F']+[uUlL]*|0b[01']+[uUlL]*|\d[\d']*\.?[\d']*(?:e[+-]?\d+)?[fFlLuU]*(?:_\w+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(->|::|<=>|<<|>>|\+\+|--|&&|\|\||[+\-*\/%&|^<>=!]=?|\.\.\.)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Function call or template
        if ($rest =~ /^(\w+)(?=\s*[<(])/) {
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
