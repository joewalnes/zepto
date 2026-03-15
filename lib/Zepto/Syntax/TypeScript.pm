package Zepto::Syntax::TypeScript;
# =============================================================================
# JavaScript/TypeScript/JSX/TSX Syntax Grammar
# =============================================================================
#
# This is the unified grammar for JavaScript, TypeScript, JSX, and TSX.
# Since TypeScript is a superset of JavaScript, we handle both here.
# JSX/TSX support includes element tags and attributes.
#
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

# JavaScript keywords (also valid in TypeScript)
my $JS_KEYWORDS = qr/\b(?:
    async | await | break | case | catch | class | const | continue |
    debugger | default | delete | do | else | export | extends |
    finally | for | function | if | import | in | instanceof |
    let | new | of | return | static | super | switch | this |
    throw | try | typeof | var | void | while | with | yield |
    true | false | null | undefined | NaN | Infinity
)\b/x;

# TypeScript-specific keywords
my $TS_KEYWORDS = qr/\b(?:
    abstract | as | asserts | declare | enum | implements |
    interface | is | keyof | namespace | never | override |
    private | protected | public | readonly | type | unknown |
    infer | satisfies | module | require | global | using
)\b/x;

# TypeScript built-in types
my $TS_TYPES = qr/\b(?:
    any | bigint | boolean | never | null | number | object |
    string | symbol | undefined | unknown | void |
    Partial | Required | Readonly | Record | Pick | Omit |
    Exclude | Extract | NonNullable | Parameters | ReturnType |
    InstanceType | ThisType | Awaited
)\b/x;

# Common JS/TS built-in objects and types
my $BUILTINS = qr/\b(?:
    Array | Boolean | Date | Error | Function | JSON | Map | Math |
    Number | Object | Promise | Proxy | Reflect | RegExp | Set | String | Symbol |
    WeakMap | WeakSet | BigInt | ArrayBuffer | DataView |
    Int8Array | Uint8Array | Int16Array | Uint16Array |
    Int32Array | Uint32Array | Float32Array | Float64Array |
    console | document | window | global | globalThis | process |
    module | exports | require | Buffer
)\b/x;

# Returns all keywords, types, and builtins as a flat list for external consumers
sub keyword_list {
    return [qw(
        async await break case catch class const continue
        debugger default delete do else export extends
        finally for function if import in instanceof
        let new of return static super switch this
        throw try typeof var void while with yield
        true false null undefined NaN Infinity

        abstract as asserts declare enum implements
        interface is keyof namespace never override
        private protected public readonly type unknown
        infer satisfies module require global using

        any bigint boolean number object
        string symbol
        Partial Required Readonly Record Pick Omit
        Exclude Extract NonNullable Parameters ReturnType
        InstanceType ThisType Awaited

        Array Boolean Date Error Function JSON Map Math
        Number Object Promise Proxy Reflect RegExp Set String Symbol
        WeakMap WeakSet BigInt ArrayBuffer DataView
        Int8Array Uint8Array Int16Array Uint16Array
        Int32Array Uint32Array Float32Array Float64Array
        console document window globalThis process
        exports Buffer
    )];
}

# JSX/TSX: Check if we're likely in JSX context
sub _is_jsx_context {
    my ($before) = @_;
    # JSX tags typically appear after: return, =, (, {, ,, :, &&, ||, ?, =>
    return $before =~ /(?:return|[=(\[{,:?]|&&|\|\||=>)\s*$/;
}

# Tokenize template literal with ${...} interpolation highlighting
# Returns (tokens_ref, remaining_pos, end_state)
sub _tokenize_template_literal {
    my ($self, $line, $start_pos) = @_;
    my @tokens;
    my $pos = $start_pos;
    my $len = length($line);

    # Start of template literal string portion
    my $str_start = $pos;
    $pos++;  # Skip opening backtick

    while ($pos < $len) {
        my $char = substr($line, $pos, 1);

        # Check for ${
        if ($char eq '$' && $pos + 1 < $len && substr($line, $pos + 1, 1) eq '{') {
            # Emit string portion before interpolation
            if ($pos > $str_start) {
                push @tokens, _token($str_start, $pos, TOKEN_STRING);
            }

            # Emit ${ as punctuation
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;

            # Parse the interpolation, tracking brace depth
            my $brace_depth = 1;
            my $expr_start = $pos;

            while ($pos < $len && $brace_depth > 0) {
                my $c = substr($line, $pos, 1);

                if ($c eq '{') {
                    $brace_depth++;
                    $pos++;
                } elsif ($c eq '}') {
                    $brace_depth--;
                    if ($brace_depth == 0) {
                        # End of interpolation - tokenize the expression
                        if ($pos > $expr_start) {
                            my $expr = substr($line, $expr_start, $pos - $expr_start);
                            my ($expr_tokens, $_state) = $self->_tokenize_expression($expr, $expr_start);
                            push @tokens, @$expr_tokens;
                        }
                        # Emit closing } as punctuation
                        push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                        $pos++;
                        $str_start = $pos;  # Start new string portion
                        last;
                    } else {
                        $pos++;
                    }
                } elsif ($c eq '"' || $c eq "'") {
                    # Skip string inside interpolation
                    my $quote = $c;
                    $pos++;
                    while ($pos < $len) {
                        my $sc = substr($line, $pos, 1);
                        if ($sc eq '\\' && $pos + 1 < $len) {
                            $pos += 2;  # Skip escaped char
                        } elsif ($sc eq $quote) {
                            $pos++;
                            last;
                        } else {
                            $pos++;
                        }
                    }
                } elsif ($c eq '`') {
                    # Nested template literal - skip it (simplified)
                    $pos++;
                    while ($pos < $len && substr($line, $pos, 1) ne '`') {
                        if (substr($line, $pos, 1) eq '\\') {
                            $pos++;
                        }
                        $pos++;
                    }
                    $pos++ if $pos < $len;  # Skip closing backtick
                } else {
                    $pos++;
                }
            }

            # If brace depth > 0, we didn't find the closing brace (multiline)
            if ($brace_depth > 0) {
                # Emit remaining expression content as code
                if ($pos > $expr_start) {
                    my $expr = substr($line, $expr_start, $pos - $expr_start);
                    my ($expr_tokens, $_state) = $self->_tokenize_expression($expr, $expr_start);
                    push @tokens, @$expr_tokens;
                }
                # Return with special state for template in interpolation
                # For now, just treat rest as expression
                return (\@tokens, $pos, STATE_STRING_TEMPLATE);
            }
            next;
        }

        # Check for escape
        if ($char eq '\\' && $pos + 1 < $len) {
            $pos += 2;
            next;
        }

        # Check for closing backtick
        if ($char eq '`') {
            # Emit final string portion including backtick
            push @tokens, _token($str_start, $pos + 1, TOKEN_STRING);
            return (\@tokens, $pos + 1, STATE_NORMAL);
        }

        $pos++;
    }

    # End of line without closing backtick - multiline template
    if ($pos > $str_start) {
        push @tokens, _token($str_start, $pos, TOKEN_STRING);
    }
    return (\@tokens, $pos, STATE_STRING_TEMPLATE);
}

# Tokenize a JavaScript expression (used inside ${...})
sub _tokenize_expression {
    my ($self, $expr, $offset) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($expr);

    while ($pos < $len) {
        my $rest = substr($expr, $pos);

        # Skip whitespace
        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # String literals
        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($offset + $pos, $offset + $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Keywords
        if ($rest =~ /^($JS_KEYWORDS)/) {
            push @tokens, _token($offset + $pos, $offset + $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Built-in objects
        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($offset + $pos, $offset + $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?n?)/) {
            push @tokens, _token($offset + $pos, $offset + $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(=>|===|!==|==|!=|<=|>=|&&|\|\||\?\?|\?\.|[+\-*\/%&|^~<>=!?:])/) {
            push @tokens, _token($offset + $pos, $offset + $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Function call
        if ($rest =~ /^(\w+)(?=\s*\()/) {
            push @tokens, _token($offset + $pos, $offset + $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Constants (UPPER_CASE)
        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($offset + $pos, $offset + $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # PascalCase types
        if ($rest =~ /^([A-Z][a-zA-Z0-9]*)\b/) {
            push @tokens, _token($offset + $pos, $offset + $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Identifiers (skip them - plain text)
        if ($rest =~ /^([a-z_]\w*)/i) {
            $pos += length($1);
            next;
        }

        # Punctuation
        if ($rest =~ /^([(){}\[\],.;])/) {
            push @tokens, _token($offset + $pos, $offset + $pos + 1, TOKEN_PUNCTUATION);
            $pos++;
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

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

    # Continue template literal (from previous line)
    if ($state == STATE_STRING_TEMPLATE) {
        # Process template content looking for ${...} or closing `
        my $str_start = 0;
        while ($pos < $len) {
            my $char = substr($line, $pos, 1);

            # Check for ${
            if ($char eq '$' && $pos + 1 < $len && substr($line, $pos + 1, 1) eq '{') {
                if ($pos > $str_start) {
                    push @tokens, _token($str_start, $pos, TOKEN_STRING);
                }
                push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
                $pos += 2;

                # Parse interpolation with brace depth
                my $brace_depth = 1;
                my $expr_start = $pos;
                while ($pos < $len && $brace_depth > 0) {
                    my $c = substr($line, $pos, 1);
                    if ($c eq '{') { $brace_depth++; $pos++; }
                    elsif ($c eq '}') {
                        $brace_depth--;
                        if ($brace_depth == 0) {
                            if ($pos > $expr_start) {
                                my $expr = substr($line, $expr_start, $pos - $expr_start);
                                my ($expr_tokens, $_st) = $self->_tokenize_expression($expr, $expr_start);
                                push @tokens, @$expr_tokens;
                            }
                            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                            $pos++;
                            $str_start = $pos;
                            last;
                        } else { $pos++; }
                    }
                    elsif ($c eq '"' || $c eq "'") {
                        my $q = $c; $pos++;
                        while ($pos < $len) {
                            my $sc = substr($line, $pos, 1);
                            if ($sc eq '\\' && $pos + 1 < $len) { $pos += 2; }
                            elsif ($sc eq $q) { $pos++; last; }
                            else { $pos++; }
                        }
                    }
                    else { $pos++; }
                }
                if ($brace_depth > 0) {
                    # Unclosed interpolation - continue on next line
                    if ($pos > $expr_start) {
                        my $expr = substr($line, $expr_start, $pos - $expr_start);
                        my ($expr_tokens, $_st) = $self->_tokenize_expression($expr, $expr_start);
                        push @tokens, @$expr_tokens;
                    }
                    return (\@tokens, STATE_STRING_TEMPLATE);
                }
                next;
            }

            # Check for escape
            if ($char eq '\\' && $pos + 1 < $len) {
                $pos += 2;
                next;
            }

            # Check for closing backtick
            if ($char eq '`') {
                push @tokens, _token($str_start, $pos + 1, TOKEN_STRING);
                $pos++;
                $state = STATE_NORMAL;
                last;
            }

            $pos++;
        }

        # If we reached end of line without closing, emit remaining as string
        if ($state == STATE_STRING_TEMPLATE) {
            if ($pos > $str_start) {
                push @tokens, _token($str_start, $pos, TOKEN_STRING);
            }
            return (\@tokens, STATE_STRING_TEMPLATE);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Skip whitespace
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

        # Decorator/attribute (@decorator)
        if ($rest =~ /^(@[\w.]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Template literal (backtick string) with ${...} interpolation highlighting
        if ($rest =~ /^`/) {
            my ($tpl_tokens, $new_pos, $new_state) = $self->_tokenize_template_literal($line, $pos);
            push @tokens, @$tpl_tokens;
            if ($new_state == STATE_STRING_TEMPLATE) {
                return (\@tokens, STATE_STRING_TEMPLATE);
            }
            $pos = $new_pos;
            next;
        }

        # Regular strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Regex literal (context-aware)
        if ($rest =~ m{^(/(?![/*])(?:[^/\\]|\\.)+/[gimsuy]*)}) {
            my $regex_match = $1;
            my $before = $pos > 0 ? substr($line, 0, $pos) : '';
            if ($before =~ /(?:^|[=(\[{,;:!&|?]|return|case)\s*$/) {
                push @tokens, _token($pos, $pos + length($regex_match), TOKEN_REGEX);
                $pos += length($regex_match);
                next;
            }
        }

        # JSX/TSX: Self-closing tag <Component /> or <div />
        if ($rest =~ m{^(<)(/?)([A-Z][\w.]*|[a-z][\w-]*)([^>]*?)(/?>)}) {
            my $before = $pos > 0 ? substr($line, 0, $pos) : '';
            if (_is_jsx_context($before) || $2 eq '/') {  # Opening context or closing tag
                my ($open, $slash, $tag, $attrs, $close) = ($1, $2, $3, $4, $5);
                # < or </
                push @tokens, _token($pos, $pos + length($open) + length($slash), TOKEN_PUNCTUATION);
                $pos += length($open) + length($slash);
                # Tag name (PascalCase = component, lowercase = HTML element)
                my $tag_type = ($tag =~ /^[A-Z]/) ? TOKEN_TYPE : TOKEN_TAG;
                push @tokens, _token($pos, $pos + length($tag), $tag_type);
                $pos += length($tag);
                # Parse attributes within the tag
                my $attr_pos = 0;
                while ($attr_pos < length($attrs)) {
                    my $attr_rest = substr($attrs, $attr_pos);
                    if ($attr_rest =~ /^(\s+)/) {
                        $attr_pos += length($1);
                    } elsif ($attr_rest =~ /^([\w-]+)(=)/) {
                        push @tokens, _token($pos + $attr_pos, $pos + $attr_pos + length($1), TOKEN_ATTRIBUTE);
                        $attr_pos += length($1);
                        push @tokens, _token($pos + $attr_pos, $pos + $attr_pos + 1, TOKEN_OPERATOR);
                        $attr_pos += 1;
                    } elsif ($attr_rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
                        push @tokens, _token($pos + $attr_pos, $pos + $attr_pos + length($1), TOKEN_STRING);
                        $attr_pos += length($1);
                    } elsif ($attr_rest =~ /^(\{)/) {
                        push @tokens, _token($pos + $attr_pos, $pos + $attr_pos + 1, TOKEN_PUNCTUATION);
                        $attr_pos += 1;
                    } else {
                        $attr_pos++;
                    }
                }
                $pos += length($attrs);
                # /> or >
                push @tokens, _token($pos, $pos + length($close), TOKEN_PUNCTUATION);
                $pos += length($close);
                next;
            }
        }

        # interface/type/enum declaration
        if ($rest =~ /^(interface|type|enum)\s+(\w+)/) {
            my ($kw, $name) = ($1, $2);
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            push @tokens, _token($pos, $pos + length($name), TOKEN_TYPE);
            $pos += length($name);
            next;
        }

        # function/class declaration
        if ($rest =~ /^(function|class)\s+(\w+)/) {
            my ($kw, $name) = ($1, $2);
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            my $ttype = ($kw eq 'class') ? TOKEN_TYPE : TOKEN_FUNCTION;
            push @tokens, _token($pos, $pos + length($name), $ttype);
            $pos += length($name);
            next;
        }

        # TypeScript keywords
        if ($rest =~ /^($TS_KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # TypeScript types
        if ($rest =~ /^($TS_TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # JavaScript keywords
        if ($rest =~ /^($JS_KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Built-in objects
        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Numbers (including bigint)
        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?n?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(=>|===|!==|==|!=|<=|>=|&&|\|\||\?\?|\?\.|<<|>>>|>>|\*\*|\.\.\.|[+\-*\/%&|^~<>=!?:])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Function call or generic
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

        # PascalCase type name (only at word boundary start)
        if ($rest =~ /^([A-Z][a-zA-Z0-9]*)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Regular identifiers (variables, etc.) - consume as plain text
        # This prevents partial matches like "File" in "readFile"
        if ($rest =~ /^([a-z_]\w*)/i) {
            # Just skip identifiers - they become plain text (default fg color)
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
