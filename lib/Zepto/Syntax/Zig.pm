package Zepto::Syntax::Zig;
# =============================================================================
# Zig Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $KEYWORDS = qr/\b(?:
    addrspace | align | allowzero | and | anyframe | anytype |
    asm | async | await | break | callconv | catch | comptime |
    const | continue | defer | else | enum | errdefer | error |
    export | extern | false | fn | for | if | inline |
    linksection | noalias | noinline | nosuspend | null | opaque |
    or | orelse | packed | pub | resume | return | struct |
    suspend | switch | test | threadlocal | true | try |
    undefined | union | unreachable | usingnamespace | var |
    volatile | while
)\b/x;

my $TYPES = qr/\b(?:
    i8 | i16 | i32 | i64 | i128 | isize |
    u8 | u16 | u32 | u64 | u128 | usize |
    f16 | f32 | f64 | f80 | f128 |
    bool | void | noreturn | type | anyerror | anyopaque |
    c_short | c_ushort | c_int | c_uint | c_long | c_ulong |
    c_longlong | c_ulonglong | c_longdouble | c_void
)\b/x;

# Built-in functions start with @
my $BUILTINS = qr/\@(?:
    addWithOverflow | alignCast | alignOf | as | asyncCall |
    atomicLoad | atomicRmw | atomicStore | bitCast | bitOffsetOf |
    bitReverse | bitSizeOf | boolToInt | breakpoint | byteSwap |
    call | cDefine | ceil | cImport | cInclude | clz |
    cmpxchgStrong | cmpxchgWeak | compileError | compileLog |
    ctz | cUndef | divExact | divFloor | divTrunc |
    embedFile | enumToInt | errSetCast | errorName | errorReturnTrace |
    export | extern | fence | field | fieldParentPtr |
    floatCast | floatToInt | frame | frameAddress | frameSize |
    hasDecl | hasField | import | intCast | intToEnum |
    intToFloat | intToPtr | max | memcpy | memset | min |
    mod | mulAdd | mulWithOverflow | offsetOf | panic |
    popCount | prefetch | ptrCast | ptrToInt | reduce |
    rem | returnAddress | select | setAlignStack | setEvalBranchQuota |
    setFloatMode | setRuntimeSafety | shlExact | shlWithOverflow |
    shrExact | shuffle | sizeOf | splat | sqrt | src |
    subWithOverflow | tagName | This | trap | truncate |
    Type | typeInfo | typeName | TypeOf | unionInit | Vector |
    wasmMemorySize | wasmMemoryGrow
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue multi-line string (Zig uses \\ at line start)
    # Not handling this specially - each line is independent

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line comment
        if ($rest =~ m{^(//.*)} ) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # String literal
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Character literal
        if ($rest =~ /^('(?:[^'\\]|\\.)+'?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Multi-line string (starts with \\)
        if ($rest =~ /^(\\\\.*$)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Built-in function (@name)
        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Other @identifier
        if ($rest =~ /^(\@\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
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

        # struct/enum/union declaration
        if ($rest =~ /^(const)\s+(\w+)\s*=\s*(struct|enum|union)\b/) {
            push @tokens, _token($pos, $pos + 5, TOKEN_KEYWORD);
            $pos += 5;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^const\s+(\w+)/) {
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

        # Numbers (including different bases and type suffixes)
        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(=>|->|\+\+|--|<<|>>|\+%|-%)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^([+\-*\/%&|^<>=!]=?|\.{2,3}|\?\?)/) {
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

        # CONSTANT_NAME (all caps)
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
