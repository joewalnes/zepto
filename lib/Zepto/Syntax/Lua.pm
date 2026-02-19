package Zepto::Syntax::Lua;
# =============================================================================
# Lua Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

my $KEYWORDS = qr/\b(?:
    and | break | do | else | elseif | end | false | for | function |
    goto | if | in | local | nil | not | or | repeat | return | then |
    true | until | while
)\b/x;

my $BUILTINS = qr/\b(?:
    assert | collectgarbage | dofile | error | getfenv | getmetatable |
    ipairs | load | loadfile | loadstring | module | next | pairs |
    pcall | print | rawequal | rawget | rawlen | rawset | require |
    select | setfenv | setmetatable | tonumber | tostring | type |
    unpack | xpcall | _G | _VERSION |
    coroutine | debug | io | math | os | package | string | table | utf8
)\b/x;

my $LIBRARY_FUNCS = qr/\b(?:
    coroutine\.create | coroutine\.isyieldable | coroutine\.resume |
    coroutine\.running | coroutine\.status | coroutine\.wrap | coroutine\.yield |
    debug\.debug | debug\.gethook | debug\.getinfo | debug\.getlocal |
    debug\.getmetatable | debug\.getregistry | debug\.getupvalue |
    debug\.getuservalue | debug\.sethook | debug\.setlocal |
    debug\.setmetatable | debug\.setupvalue | debug\.setuservalue |
    debug\.traceback | debug\.upvalueid | debug\.upvaluejoin |
    io\.close | io\.flush | io\.input | io\.lines | io\.open | io\.output |
    io\.popen | io\.read | io\.stderr | io\.stdin | io\.stdout |
    io\.tmpfile | io\.type | io\.write |
    math\.abs | math\.acos | math\.asin | math\.atan | math\.ceil |
    math\.cos | math\.deg | math\.exp | math\.floor | math\.fmod |
    math\.huge | math\.log | math\.max | math\.maxinteger | math\.min |
    math\.mininteger | math\.modf | math\.pi | math\.rad | math\.random |
    math\.randomseed | math\.sin | math\.sqrt | math\.tan | math\.tointeger |
    math\.type | math\.ult |
    os\.clock | os\.date | os\.difftime | os\.execute | os\.exit |
    os\.getenv | os\.remove | os\.rename | os\.setlocale | os\.time |
    os\.tmpname |
    package\.config | package\.cpath | package\.loaded | package\.loadlib |
    package\.path | package\.preload | package\.searchers | package\.searchpath |
    string\.byte | string\.char | string\.dump | string\.find | string\.format |
    string\.gmatch | string\.gsub | string\.len | string\.lower | string\.match |
    string\.pack | string\.packsize | string\.rep | string\.reverse |
    string\.sub | string\.unpack | string\.upper |
    table\.concat | table\.insert | table\.move | table\.pack | table\.remove |
    table\.sort | table\.unpack |
    utf8\.char | utf8\.charpattern | utf8\.codepoint | utf8\.codes |
    utf8\.len | utf8\.offset
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue block comment --[[ ... ]]
    if ($state == STATE_COMMENT_BLOCK) {
        if ($line =~ /^(.*?)\]\]/) {
            push @tokens, _token(0, length($1) + 2, TOKEN_COMMENT);
            $pos = length($1) + 2;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_COMMENT_BLOCK);
        }
    }

    # Continue long string [[ ... ]] or [=[ ... ]=]
    if ($state >= 10 && $state < 20) {
        my $eq_count = $state - 10;
        my $close = '\]' . ('=' x $eq_count) . '\]';
        if ($line =~ /^(.*?)$close/) {
            push @tokens, _token(0, length($1) + 2 + $eq_count, TOKEN_STRING);
            $pos = length($1) + 2 + $eq_count;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, $state);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Block comment --[[ or --[=[ etc.
        if ($rest =~ /^(--\[(=*)\[)/) {
            my $open = $1;
            my $eq_count = length($2);
            my $close = '\]' . ('=' x $eq_count) . '\]';
            if ($rest =~ /^--\[=*\[(.*?)$close/) {
                my $full_match = $&;
                push @tokens, _token($pos, $pos + length($full_match), TOKEN_COMMENT);
                $pos += length($full_match);
            } else {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_COMMENT_BLOCK);
            }
            next;
        }

        # Line comment
        if ($rest =~ /^(--.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Long string [[ or [=[ etc.
        if ($rest =~ /^(\[(=*)\[)/) {
            my $open = $1;
            my $eq_count = length($2);
            my $close = '\]' . ('=' x $eq_count) . '\]';
            if ($rest =~ /^\[=*\[(.*?)$close/) {
                my $full_match = $&;
                push @tokens, _token($pos, $pos + length($full_match), TOKEN_STRING);
                $pos += length($full_match);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, 10 + $eq_count);
            }
            next;
        }

        # String literals
        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # function declaration
        if ($rest =~ /^(function)\s+(\w+(?:[.:]\w+)*)/) {
            push @tokens, _token($pos, $pos + 8, TOKEN_KEYWORD);
            $pos += 8;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^(\w+(?:[.:]\w+)*)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        # local function
        if ($rest =~ /^(local)\s+(function)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 5, TOKEN_KEYWORD);
            $pos += 5;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            push @tokens, _token($pos, $pos + 8, TOKEN_KEYWORD);
            $pos += 8;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^(\w+)/) {
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

        # Built-in functions
        if ($rest =~ /^($BUILTINS)(?=\s*[.(])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Built-in values
        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Numbers (hex, float, scientific, with optional suffixes)
        if ($rest =~ /^(0x[0-9a-fA-F]+(?:\.[0-9a-fA-F]*)?(?:p[+-]?\d+)?|\d+\.?\d*(?:e[+-]?\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(\.\.\.?|==|~=|<=|>=|<<|>>|\/\/|[+\-*\/%^#<>=])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Function call
        if ($rest =~ /^(\w+)(?=\s*[({"])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Method call obj:method
        if ($rest =~ /^(\w+)(?=\s*:)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # CONSTANT_NAME
        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
