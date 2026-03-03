package Zepto::Syntax::Shell;
# =============================================================================
# Shell (Bash/sh) Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '#' }

my $KEYWORDS = qr/\b(?:
    if | then | else | elif | fi |
    case | esac | in |
    for | while | until | do | done |
    function | return | exit |
    break | continue |
    select | time | coproc |
    true | false
)\b/x;

my $BUILTINS = qr/\b(?:
    alias | bg | cd | echo | eval | exec | export | fg | getopts |
    hash | help | history | jobs | kill | let | local | popd |
    printf | pushd | pwd | read | readonly | set | shift | shopt |
    source | test | trap | type | typeset | ulimit | umask | unalias |
    unset | wait
)\b/x;

my $COMMANDS = qr/\b(?:
    awk | cat | chmod | cp | curl | cut | diff | find | grep | gzip |
    head | ls | make | mkdir | mv | rm | sed | sort | ssh | tail |
    tar | touch | tr | wc | wget | xargs
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    if ($state == STATE_STRING_DOUBLE) {
        if ($line =~ /^(.*?)(?<!\\)"/) {
            push @tokens, _token(0, length($1) + 1, TOKEN_STRING);
            $pos = length($1) + 1;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_STRING_DOUBLE);
        }
    }

    if ($state == STATE_STRING_SINGLE) {
        if ($line =~ /^(.*?)'/) {
            push @tokens, _token(0, length($1) + 1, TOKEN_STRING);
            $pos = length($1) + 1;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_STRING_SINGLE);
        }
    }

    if ($pos == 0 && $line =~ /^(#!.*)/) {
        push @tokens, _token(0, length($1), TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        if ($rest =~ /^"/) {
            if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_DOUBLE);
            }
            next;
        }

        if ($rest =~ /^'/) {
            if ($rest =~ /^('(?:[^'])*')/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_SINGLE);
            }
            next;
        }

        if ($rest =~ /^(\$\{)(\w+)/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            push @tokens, _token($pos, $pos + length($2), TOKEN_VARIABLE);
            $pos += length($2);
            next;
        }

        if ($rest =~ /^(\$[\w]+|\$[?!#\$@*\-_0-9])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\w+)\s*\(\s*\)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(function)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^function\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^($COMMANDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(0x[0-9a-fA-F]+|\d+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(>>|>&|<&|<<|<>|\|&|\||&&|&|;|[<>])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(-[a-zA-Z]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\[\[|\]\]|\[|\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_PUNCTUATION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\w+)(=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        my $before = $pos > 0 ? substr($line, 0, $pos) : '';
        if ($before =~ /(?:^|\||;|&&|&|\()\s*$/ && $rest =~ /^(\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
