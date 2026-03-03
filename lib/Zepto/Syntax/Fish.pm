package Zepto::Syntax::Fish;
# =============================================================================
# Fish Shell Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub line_comment_prefix { '#' }

my $KEYWORDS = qr/\b(?:
    if | else | end | for | in | while | switch | case |
    function | return | begin | break | continue |
    and | or | not | true | false |
    set | set_color | status | test | argparse
)\b/x;

my $BUILTINS = qr/\b(?:
    abbr | alias | bg | bind | block | builtin | cd | command |
    commandline | complete | contains | count | dirh | dirs |
    disown | echo | emit | eval | exec | exit | fg | fish |
    fish_add_path | fish_breakpoint_prompt | fish_config | fish_greeting |
    fish_indent | fish_key_reader | fish_mode_prompt | fish_opt |
    fish_prompt | fish_right_prompt | fish_status_to_signal |
    fish_title | fish_update_completions | fish_vcs_prompt |
    funced | funcsave | functions | history | isatty | jobs |
    math | nextd | open | popd | prevd | printf | prompt_login |
    prompt_pwd | psub | pushd | pwd | random | read | realpath |
    set_color | source | status | string | suspend | test |
    time | trap | type | ulimit | umask | vared | wait
)\b/x;

my $COMMANDS = qr/\b(?:
    awk | cat | chmod | cp | curl | cut | diff | find | git |
    grep | gzip | head | kill | less | ln | ls | make | mkdir |
    mv | rm | sed | sort | ssh | sudo | tail | tar | touch |
    tr | wc | wget | xargs
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue multi-line single-quoted string
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

    # Continue multi-line double-quoted string
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

    # Shebang
    if ($pos == 0 && $line =~ /^(#!.*)/) {
        push @tokens, _token(0, length($1), TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Comment
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Single-quoted string (no escapes in fish)
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

        # Double-quoted string
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

        # Variable expansion $var, $var[1], $PATH
        if ($rest =~ /^(\$[\w]+(?:\[\d+(?:\.\.\d+)?\])?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Command substitution (...)
        if ($rest =~ /^(\()/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        if ($rest =~ /^(\))/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Function definition
        if ($rest =~ /^(function\s+)([\w.-]+)/) {
            push @tokens, _token($pos, $pos + length($1) - 1, TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^([\w.-]+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
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

        # Builtins
        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Common commands
        if ($rest =~ /^($COMMANDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F]+|\d+\.?\d*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators and redirections
        if ($rest =~ /^(>>|\^>|2>|>&|<|>|\||\|\||&&|;|&)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Flags
        if ($rest =~ /^(-[\w-]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Brackets
        if ($rest =~ /^([\[\]])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Assignment with set
        if ($rest =~ /^(\w+)(=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, $state);
}

1;
