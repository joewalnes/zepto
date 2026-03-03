package Zepto::Syntax::INI;
# =============================================================================
# INI File Syntax Grammar
# =============================================================================
# Supports standard INI format with sections, keys, values, and comments

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { ';' }

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Skip leading whitespace
        if ($rest =~ /^(\s+)/) {
            $pos += length($1);
            next;
        }

        # Comment (# or ;)
        if ($rest =~ /^([#;].*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Section header [section] or [section.subsection]
        if ($rest =~ /^(\[)([^\]]+)(\])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($2), TOKEN_TYPE);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Key = value pair
        if ($rest =~ /^([\w.-]+)(\s*)(=)/) {
            # Key
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            # Whitespace before =
            $pos += length($2);
            # Equals sign
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;

            # Parse the value part
            $rest = substr($line, $pos);

            # Skip whitespace after =
            if ($rest =~ /^(\s+)/) {
                $pos += length($1);
                $rest = substr($line, $pos);
            }

            # Check for inline comment and capture value before it
            if ($rest =~ /^(.+?)(\s*[#;].*)$/) {
                my $value = $1;
                my $comment = $2;

                # Tokenize the value
                $value =~ s/\s+$//;  # Trim trailing whitespace from value
                if (length($value) > 0) {
                    _tokenize_value(\@tokens, $pos, $value);
                    $pos += length($value);
                }

                # Skip whitespace before comment
                $rest = substr($line, $pos);
                if ($rest =~ /^(\s+)/) {
                    $pos += length($1);
                }

                # Tokenize the comment
                $rest = substr($line, $pos);
                if ($rest =~ /^([#;].*)/) {
                    push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
                    $pos += length($1);
                }
            } else {
                # No inline comment - value goes to end of line
                $rest =~ s/\s+$//;  # Trim trailing whitespace
                if (length($rest) > 0) {
                    _tokenize_value(\@tokens, $pos, $rest);
                    $pos += length($rest);
                }
            }
            last;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

# Helper to tokenize a value
sub _tokenize_value {
    my ($tokens, $pos, $value) = @_;

    # Quoted string
    if ($value =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')(.*)$/) {
        push @$tokens, _token($pos, $pos + length($1), TOKEN_STRING);
        $pos += length($1);
        if (length($2) > 0) {
            _tokenize_value($tokens, $pos, $2);
        }
    }
    # Boolean
    elsif ($value =~ /^(true|false|yes|no|on|off)\b/i) {
        push @$tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
        my $rest = substr($value, length($1));
        if (length($rest) > 0) {
            _tokenize_value($tokens, $pos + length($1), $rest);
        }
    }
    # Number
    elsif ($value =~ /^(-?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)\b/i) {
        push @$tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
        my $rest = substr($value, length($1));
        if (length($rest) > 0) {
            _tokenize_value($tokens, $pos + length($1), $rest);
        }
    }
    # Variable reference ${var} or %(var)s or $var
    elsif ($value =~ /^(\$\{[^}]+\}|\$\([^)]+\)|\%\([^)]+\)s?|\$\w+)/) {
        push @$tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
        my $rest = substr($value, length($1));
        if (length($rest) > 0) {
            _tokenize_value($tokens, $pos + length($1), $rest);
        }
    }
    # Plain string value (unquoted)
    else {
        push @$tokens, _token($pos, $pos + length($value), TOKEN_STRING);
    }
}

1;
