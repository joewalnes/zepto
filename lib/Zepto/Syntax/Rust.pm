package Zepto::Syntax::Rust;
# =============================================================================
# Rust Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $KEYWORDS = qr/\b(?:
    as | async | await | break | const | continue | crate | dyn |
    else | enum | extern | false | fn | for | if | impl | in |
    let | loop | match | mod | move | mut | pub | ref | return |
    self | Self | static | struct | super | trait | true | type |
    unsafe | use | where | while |
    abstract | become | box | do | final | macro | override |
    priv | try | typeof | unsized | virtual | yield
)\b/x;

my $TYPES = qr/\b(?:
    bool | char | str |
    i8 | i16 | i32 | i64 | i128 | isize |
    u8 | u16 | u32 | u64 | u128 | usize |
    f32 | f64 |
    String | Vec | Box | Rc | Arc | Cell | RefCell |
    Option | Result | Some | None | Ok | Err |
    HashMap | HashSet | BTreeMap | BTreeSet
)\b/x;

my $BUILTINS = qr/\b(?:
    drop | panic | print | println | eprint | eprintln |
    format | vec | assert | assert_eq | assert_ne |
    debug_assert | debug_assert_eq | debug_assert_ne |
    todo | unimplemented | unreachable
)\b/x;

sub keyword_list {
    return [
        # Keywords
        qw(as async await break const continue crate dyn
           else enum extern false fn for if impl in
           let loop match mod move mut pub ref return
           self Self static struct super trait true type
           unsafe use where while
           abstract become box do final macro override
           priv try typeof unsized virtual yield),
        # Types
        qw(bool char str
           i8 i16 i32 i64 i128 isize
           u8 u16 u32 u64 u128 usize
           f32 f64
           String Vec Box Rc Arc Cell RefCell
           Option Result Some None Ok Err
           HashMap HashSet BTreeMap BTreeSet),
        # Builtins / macros
        qw(drop panic print println eprint eprintln
           format vec assert assert_eq assert_ne
           debug_assert debug_assert_eq debug_assert_ne
           todo unimplemented unreachable),
    ];
}

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue block comment (supports nesting via state value > 4)
    if ($state >= STATE_COMMENT_BLOCK) {
        my $depth = $state - STATE_COMMENT_BLOCK + 1;
        my $i = 0;
        while ($i < $len) {
            if (substr($line, $i, 2) eq '/*') {
                $depth++;
                $i += 2;
            } elsif (substr($line, $i, 2) eq '*/') {
                $depth--;
                if ($depth == 0) {
                    push @tokens, _token(0, $i + 2, TOKEN_COMMENT);
                    $pos = $i + 2;
                    $state = STATE_NORMAL;
                    last;
                }
                $i += 2;
            } else {
                $i++;
            }
        }
        if ($state != STATE_NORMAL) {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_COMMENT_BLOCK + $depth - 1);
        }
    }

    # Continue raw string
    if ($state == STATE_STRING_RAW) {
        if ($line =~ /^(.*?)"#*/) {
            push @tokens, _token(0, length($&), TOKEN_STRING);
            $pos = length($&);
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_STRING_RAW);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line comment (including doc comments)
        if ($rest =~ m{^(//[!/]?.*)} ) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Block comment (including doc comments)
        if ($rest =~ m{^(/\*[*!]?)}) {
            # Check for nested comments
            my $depth = 1;
            my $i = length($1);
            while ($i < length($rest) && $depth > 0) {
                if (substr($rest, $i, 2) eq '/*') {
                    $depth++;
                    $i += 2;
                } elsif (substr($rest, $i, 2) eq '*/') {
                    $depth--;
                    $i += 2;
                } else {
                    $i++;
                }
            }
            if ($depth == 0) {
                push @tokens, _token($pos, $pos + $i, TOKEN_COMMENT);
                $pos += $i;
            } else {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_COMMENT_BLOCK + $depth - 1);
            }
            next;
        }

        # Attribute
        if ($rest =~ /^(#!?\[[\w:(,)\s"'=]+\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^(#!?\[)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Raw string literal
        if ($rest =~ /^(r#*)"/) {
            my $prefix = $1;
            my $hashes = $prefix =~ tr/#//;
            my $pattern = '"' . ('#' x $hashes);
            if ($rest =~ /^r#*"(.*?)$pattern/) {
                my $full_len = length($prefix) + 1 + length($1) + 1 + $hashes;
                push @tokens, _token($pos, $pos + $full_len, TOKEN_STRING);
                $pos += $full_len;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_RAW);
            }
            next;
        }

        # Byte string
        if ($rest =~ /^(b"(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Regular string
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Character/byte literal
        if ($rest =~ /^(b?'(?:[^'\\]|\\.)')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Lifetime
        if ($rest =~ /^('(?:static|\w+))\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # fn declaration
        if ($rest =~ /^(fn)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_KEYWORD);
            $pos += 2;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^fn\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        # struct/enum/trait/type/mod declaration
        if ($rest =~ /^(struct|enum|trait|type|mod)\s+(\w+)/) {
            my $kw = $1;
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:struct|enum|trait|type|mod)\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        # Macro invocation
        if ($rest =~ /^(\w+)!/) {
            push @tokens, _token($pos, $pos + length($1) + 1, TOKEN_FUNCTION);
            $pos += length($1) + 1;
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

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?(?:i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(=>|->|::|&&|\|\||<<|>>|[+\-*\/%&|^<>=!]=?|\.\.|\.\.=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Function call
        if ($rest =~ /^(\w+)(?=\s*[(<])/) {
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
