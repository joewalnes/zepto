package Zepto::Syntax::Thrift;
# =============================================================================
# Apache Thrift IDL Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

# Thrift keywords
my $KEYWORDS = qr/\b(?:
    namespace | include | cpp_include | php_namespace | py_module |
    java_package | cocoa_package | csharp_namespace | ruby_namespace |
    perl_package | smalltalk_category | xsd_namespace |
    const | typedef | enum | struct | union | exception | service |
    extends | throws | oneway | async | void |
    required | optional | readonly |
    true | false
)\b/x;

# Thrift base types
my $TYPES = qr/\b(?:
    bool | byte | i8 | i16 | i32 | i64 | double | string | binary |
    slist | map | list | set | cpp_type
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

        # Line comments (// or #)
        if ($rest =~ m{^(//.*|#.*)}) {
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

        # String (double-quoted)
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # String (single-quoted)
        if ($rest =~ /^('(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Namespace language specifier
        if ($rest =~ /^(namespace)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 9, TOKEN_KEYWORD);
            $pos += 9;
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s+)(\w+)/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_TYPE);
                $pos += length($2);
            }
            next;
        }

        # Include directive
        if ($rest =~ /^(include|cpp_include)\s*("(?:[^"\\]|\\.)*")/) {
            my $kw_len = length($1);
            push @tokens, _token($pos, $pos + $kw_len, TOKEN_KEYWORD);
            $pos += $kw_len;
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s*)("(?:[^"\\]|\\.)*")/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_STRING);
                $pos += length($2);
            }
            next;
        }

        # Service/struct/enum/exception/union definition
        if ($rest =~ /^(service|struct|enum|exception|union|typedef)\s+(\w+)/) {
            my $kw_len = length($1);
            push @tokens, _token($pos, $pos + $kw_len, TOKEN_KEYWORD);
            $pos += $kw_len;
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s+)(\w+)/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + length($2), TOKEN_TYPE);
                $pos += length($2);
            }
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Types
        if ($rest =~ /^($TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Generic type reference (PascalCase identifiers)
        if ($rest =~ /^([A-Z]\w*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:e[+-]?\d+)?))/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Field ID (1: fieldname)
        if ($rest =~ /^(\d+)(\s*:)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            push @tokens, _token($pos, $pos + length($2), TOKEN_OPERATOR);
            $pos += length($2);
            next;
        }

        # Operators and punctuation
        if ($rest =~ /^([=<>,;:{}()\[\]])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # Function name (word followed by parenthesis)
        if ($rest =~ /^(\w+)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
