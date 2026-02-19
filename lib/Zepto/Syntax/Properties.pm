package Zepto::Syntax::Properties;
# =============================================================================
# Java Properties File Syntax Grammar
# =============================================================================
# Supports .properties format with key=value, key:value, comments, and continuations

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

# Custom state for line continuation
use constant STATE_CONTINUATION => 10;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Handle continuation from previous line (value continues)
    if ($state == STATE_CONTINUATION) {
        # Check if this line also continues
        my $continues = ($line =~ /\\$/);

        # Skip leading whitespace in continuation
        if ($line =~ /^(\s+)/) {
            $pos = length($1);
        }

        if ($pos < $len) {
            my $value_end = $continues ? $len - 1 : $len;
            if ($value_end > $pos) {
                push @tokens, _token($pos, $value_end, TOKEN_STRING);
            }
            if ($continues) {
                push @tokens, _token($len - 1, $len, TOKEN_OPERATOR);
            }
        }

        return (\@tokens, $continues ? STATE_CONTINUATION : STATE_NORMAL);
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Skip leading whitespace
        if ($rest =~ /^(\s+)/) {
            $pos += length($1);
            next;
        }

        # Comment (# or !)
        if ($rest =~ /^([#!].*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Key-value pair: key = value, key : value, or key value
        if ($rest =~ /^([\w.-]+(?:\\.[\w.-]+)*)/) {
            my $key = $1;
            push @tokens, _token($pos, $pos + length($key), TOKEN_VARIABLE);
            $pos += length($key);

            $rest = substr($line, $pos);

            # Skip whitespace
            if ($rest =~ /^(\s+)/) {
                $pos += length($1);
                $rest = substr($line, $pos);
            }

            # Separator (= or : or whitespace already consumed)
            if ($rest =~ /^([=:])/) {
                push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
                $pos += 1;
                $rest = substr($line, $pos);
            }

            # Skip whitespace after separator
            if ($rest =~ /^(\s+)/) {
                $pos += length($1);
                $rest = substr($line, $pos);
            }

            # Value (rest of line, may have continuation)
            if (length($rest) > 0) {
                my $continues = ($rest =~ /\\$/);
                my $value_end = $continues ? $len - 1 : $len;

                if ($value_end > $pos) {
                    # Tokenize the value
                    my $value = substr($line, $pos, $value_end - $pos);
                    _tokenize_value(\@tokens, $pos, $value);
                    $pos = $value_end;
                }

                if ($continues) {
                    push @tokens, _token($len - 1, $len, TOKEN_OPERATOR);
                    return (\@tokens, STATE_CONTINUATION);
                }
            }
            last;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

# Helper to tokenize a value, handling escape sequences and variable references
sub _tokenize_value {
    my ($tokens, $start_pos, $value) = @_;
    my $pos = 0;
    my $len = length($value);
    my $string_start = 0;

    while ($pos < $len) {
        my $rest = substr($value, $pos);

        # Variable reference ${var} or $var
        if ($rest =~ /^(\$\{[^}]+\}|\$\w+)/) {
            # Push any accumulated string before the variable
            if ($pos > $string_start) {
                push @$tokens, _token($start_pos + $string_start, $start_pos + $pos, TOKEN_STRING);
            }
            push @$tokens, _token($start_pos + $pos, $start_pos + $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            $string_start = $pos;
            next;
        }

        # Escape sequence
        if ($rest =~ /^(\\[tnr\\:=# ])/) {
            $pos += length($1);
            next;
        }

        # Unicode escape
        if ($rest =~ /^(\\u[0-9a-fA-F]{4})/) {
            $pos += length($1);
            next;
        }

        $pos++;
    }

    # Push any remaining string content
    if ($pos > $string_start) {
        push @$tokens, _token($start_pos + $string_start, $start_pos + $len, TOKEN_STRING);
    }
}

1;
