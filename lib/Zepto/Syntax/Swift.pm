package Zepto::Syntax::Swift;
# =============================================================================
# Swift Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $KEYWORDS = qr/\b(?:
    actor | any | as | associatedtype | associativity | async | await |
    break | case | catch | class | continue | convenience | default |
    defer | deinit | didSet | do | dynamic | else | enum | extension |
    fallthrough | false | fileprivate | final | for | func | get |
    guard | if | import | in | indirect | infix | init | inout |
    internal | is | isolated | lazy | left | let | macro | mutating |
    nil | nonisolated | nonmutating | none | open | operator | optional |
    override | postfix | precedence | precedencegroup | prefix | private |
    protocol | public | repeat | required | rethrows | return | right |
    safe | self | Self | set | some | static | struct | subscript |
    super | switch | throw | throws | true | try | Type | typealias |
    unowned | unsafe | var | weak | where | while | willSet
)\b/x;

my $TYPES = qr/\b(?:
    Int | Int8 | Int16 | Int32 | Int64 |
    UInt | UInt8 | UInt16 | UInt32 | UInt64 |
    Float | Float16 | Float32 | Float64 | Double |
    Bool | String | Character | Void | Never |
    Array | Dictionary | Set | Optional | Result |
    Any | AnyObject | AnyHashable | AnyClass |
    Error | Codable | Encodable | Decodable | Hashable | Equatable
)\b/x;

my $BUILTINS = qr/\b(?:
    print | debugPrint | dump | fatalError | precondition |
    preconditionFailure | assert | assertionFailure |
    min | max | abs | zip | stride | sequence | repeatElement
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue block comment (supports nesting)
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

    # Continue multi-line string
    if ($state == STATE_STRING_TEMPLATE) {
        if ($line =~ /^(.*?)"""/) {
            push @tokens, _token(0, length($1) + 3, TOKEN_STRING);
            $pos = length($1) + 3;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_STRING_TEMPLATE);
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

        # Block comment (nested)
        if ($rest =~ m{^(/\*)}) {
            my $depth = 1;
            my $i = 2;
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

        # Attribute (@attribute)
        if ($rest =~ /^(@\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Compiler directive (#if, #endif, etc.)
        if ($rest =~ /^(#\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Multi-line string literal
        if ($rest =~ /^"""/) {
            if ($rest =~ /^("""(?:[^"]|"(?!""))*""")/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_TEMPLATE);
            }
            next;
        }

        # Regular string
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # func declaration
        if ($rest =~ /^(func)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 4, TOKEN_KEYWORD);
            $pos += 4;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^func\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        # class/struct/enum/protocol/extension declaration
        if ($rest =~ /^(class|struct|enum|protocol|actor|extension)\s+(\w+)/) {
            my $kw = $1;
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:class|struct|enum|protocol|actor|extension)\s+(\w+)/) {
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
        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(->|\.\.\.|\?\?|&&|\|\||[+\-*\/%&|^<>=!]=?|\?\.?)/) {
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
