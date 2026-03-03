package Zepto::Syntax::Protobuf;
# =============================================================================
# Protocol Buffers (Protobuf) Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $KEYWORDS = qr/\b(?:
    syntax | import | weak | public | package | option | message | enum |
    service | rpc | returns | stream | oneof | map | extensions | extend |
    reserved | to | max | repeated | optional | required | group
)\b/x;

my $TYPES = qr/\b(?:
    double | float | int32 | int64 | uint32 | uint64 | sint32 | sint64 |
    fixed32 | fixed64 | sfixed32 | sfixed64 | bool | string | bytes |
    Any | Duration | Timestamp | Empty | Struct | Value | ListValue |
    NullValue | BoolValue | Int32Value | Int64Value | UInt32Value |
    UInt64Value | FloatValue | DoubleValue | StringValue | BytesValue |
    FieldMask
)\b/x;

my $CONSTANTS = qr/\b(?:
    true | false | inf | nan
)\b/x;

my $OPTIONS = qr/\b(?:
    java_package | java_outer_classname | java_multiple_files |
    java_generate_equals_and_hash | java_string_check_utf8 |
    optimize_for | go_package | cc_generic_services |
    java_generic_services | py_generic_services | deprecated |
    cc_enable_arenas | objc_class_prefix | csharp_namespace |
    swift_prefix | php_class_prefix | php_namespace |
    php_metadata_namespace | ruby_package |
    SPEED | CODE_SIZE | LITE_RUNTIME |
    allow_alias | packed | lazy | jstype | unverified_lazy |
    JS_NORMAL | JS_STRING | JS_NUMBER |
    ctype | STRING | CORD | STRING_PIECE |
    retention | RETENTION_UNKNOWN | RETENTION_RUNTIME | RETENTION_SOURCE |
    target | TARGET_TYPE_UNKNOWN | TARGET_TYPE_FILE | TARGET_TYPE_MESSAGE |
    TARGET_TYPE_FIELD | TARGET_TYPE_ONEOF | TARGET_TYPE_ENUM |
    TARGET_TYPE_ENUM_ENTRY | TARGET_TYPE_SERVICE | TARGET_TYPE_METHOD
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

        # String literal
        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # message/enum/service declaration
        if ($rest =~ /^(message|enum|service)\s+(\w+)/) {
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

        # rpc declaration
        if ($rest =~ /^(rpc)\s+(\w+)/) {
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

        # Option names (in brackets)
        if ($rest =~ /^\[(\w+(?:\.\w+)*)\]/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            my $opt_name = $1;
            push @tokens, _token($pos, $pos + length($opt_name), TOKEN_ATTRIBUTE);
            $pos += length($opt_name);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Option values
        if ($rest =~ /^($OPTIONS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
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

        # Constants
        if ($rest =~ /^($CONSTANTS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Numbers (field numbers, values)
        if ($rest =~ /^(-?0x[0-9a-fA-F]+|-?\d+\.?\d*(?:e[+-]?\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Field name followed by = (field number assignment)
        if ($rest =~ /^(\w+)(\s*=\s*)(\d+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s*)(=)/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
                $pos += 1;
            }
            next;
        }

        # Operators
        if ($rest =~ /^([=;{}\[\](),<>])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # Fully qualified type (package.Type)
        if ($rest =~ /^((?:\.?\w+)+)(?=\s+\w)/) {
            my $type_name = $1;
            # Check if it starts with uppercase (likely a type)
            if ($type_name =~ /[A-Z]/) {
                push @tokens, _token($pos, $pos + length($type_name), TOKEN_TYPE);
                $pos += length($type_name);
                next;
            }
        }

        # Type name (PascalCase)
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
