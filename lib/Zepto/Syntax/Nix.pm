package Zepto::Syntax::Nix;
# =============================================================================
# Nix Expression Language Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub line_comment_prefix { '#' }

use constant STATE_MULTI_STRING => 10;  # '' multi-line string

my $KEYWORDS = qr/\b(?:
    if | then | else | let | in | with | rec | inherit | assert |
    or | import | builtins | throw | abort
)\b/x;

my $BUILTINS = qr/\b(?:
    true | false | null |
    derivation | baseNameOf | dirOf | toString | toPath | toJSON | fromJSON |
    map | filter | foldl | foldr | head | tail | elem | elemAt | length |
    concatLists | concatMap | concatStringsSep | concatStrings |
    listToAttrs | attrNames | attrValues | hasAttr | getAttr |
    isNull | isBool | isInt | isFloat | isString | isList | isAttrs | isFunction |
    typeOf | tryEval | seq | deepSeq | trace |
    fetchurl | fetchTarball | fetchGit | fetchMercurial |
    readFile | readDir | toFile | pathExists | path |
    toXML | replaceStrings | stringLength | substring | split | match |
    add | sub | mul | div | lessThan | ceil | floor |
    intersectAttrs | removeAttrs | mapAttrs | filterAttrs |
    genList | genAttrs | sort | compareLists |
    placeholder | getContext | unsafeDiscardStringContext |
    nixPath | storeDir | currentSystem | currentTime
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue multi-line '' string
    if ($state == STATE_MULTI_STRING) {
        if ($line =~ /^(.*?)''/) {
            my $match_end = length($1) + 2;
            # Check it's not an escape ''$ or ''\
            if (length($1) > 0 && substr($line, length($1) - 1, 3) =~ /^.''[^']/) {
                # This is the end of the string
            }
            push @tokens, _token(0, $match_end, TOKEN_STRING);
            $pos = $match_end;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_MULTI_STRING);
        }
    }

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
        if ($rest =~ /^(#.*)/) {
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

        # Multi-line string '' ... ''
        if ($rest =~ /^('')(?!')/) {
            if ($rest =~ /^(''(?:(?!'')[\s\S])*'')/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_MULTI_STRING);
            }
            next;
        }

        # Double-quoted string with interpolation
        if ($rest =~ /^"/) {
            if ($rest =~ /^("(?:[^"\\$]|\\.|\$\{[^}]*\}|\$(?!\{))*")/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_DOUBLE);
            }
            next;
        }

        # Path literals
        if ($rest =~ /^(\.\/[\w.\/\-]+|\/[\w.\/\-]+|<[\w.\/\-]+>)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # URI
        if ($rest =~ /^([a-zA-Z][\w+.-]*:\/\/[\w.\/\-~?&=%#+]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Interpolation ${...}
        if ($rest =~ /^(\$\{)/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_VARIABLE);
            $pos += 2;
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Builtins
        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Builtin references builtins.xxx
        if ($rest =~ /^(builtins)(\.)(\w+)/) {
            push @tokens, _token($pos, $pos + 8, TOKEN_KEYWORD);
            $pos += 8;
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($3), TOKEN_FUNCTION);
            $pos += length($3);
            next;
        }

        # Function definition pattern: name = arg: or name = { ... }:
        if ($rest =~ /^(\w+)(?=\s*:)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(\d+\.?\d*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(\+\+|\/\/|->|==|!=|>=|<=|&&|\|\||!|\?|:|=|<|>|\+|-|\*|\/)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Punctuation
        if ($rest =~ /^([{}()\[\];.,@])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, $state);
}

1;
