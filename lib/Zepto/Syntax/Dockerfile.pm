package Zepto::Syntax::Dockerfile;
# =============================================================================
# Dockerfile Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

my $INSTRUCTIONS = qr/^(?:
    FROM | AS | MAINTAINER | RUN | CMD | LABEL | EXPOSE | ENV | ADD | COPY |
    ENTRYPOINT | VOLUME | USER | WORKDIR | ARG | ONBUILD | STOPSIGNAL |
    HEALTHCHECK | SHELL | CROSS_BUILD
)\b/xi;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Skip leading whitespace
    if ($line =~ /^(\s+)/) {
        $pos = length($1);
    }

    my $rest = substr($line, $pos);

    # Comment
    if ($rest =~ /^(#.*)/) {
        push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Parser directive (# directive=value at start of file)
    # These look like comments but are special
    if ($pos == 0 && $rest =~ /^(#\s*\w+=.*)/) {
        push @tokens, _token(0, length($1), TOKEN_ATTRIBUTE);
        return (\@tokens, STATE_NORMAL);
    }

    # Instruction keyword
    if ($rest =~ /^($INSTRUCTIONS)/i) {
        my $instr = $1;
        push @tokens, _token($pos, $pos + length($instr), TOKEN_KEYWORD);
        $pos += length($instr);
    }

    # Continue tokenizing the rest of the line
    while ($pos < $len) {
        $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Comment (can appear after continuation)
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Variable expansion ${VAR} or ${VAR:-default} or ${VAR:+value}
        if ($rest =~ /^(\$\{[^}]+\})/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Variable $VAR
        if ($rest =~ /^(\$[A-Za-z_][A-Za-z0-9_]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Quoted strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^('(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # JSON array for CMD/ENTRYPOINT/RUN
        if ($rest =~ /^(\[)/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }
        if ($rest =~ /^(\])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Flags like --from=builder, --chown=user:group
        if ($rest =~ /^(--[\w-]+=?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Image reference (name:tag or name@digest)
        if ($pos > 0 && $rest =~ /^([\w.-]+(?:\/[\w.-]+)*(?:[:@][\w.-]+)?)/) {
            my $match = $1;
            # Check if this looks like an image reference after FROM
            my $before = substr($line, 0, $pos);
            if ($before =~ /FROM\s*$/i || $before =~ /--from=$/i) {
                push @tokens, _token($pos, $pos + length($match), TOKEN_STRING);
                $pos += length($match);
                next;
            }
        }

        # Key=value pairs (for LABEL, ENV, ARG)
        if ($rest =~ /^([\w.-]+)(=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # Port numbers
        if ($rest =~ /^(\d+(?:\/(?:tcp|udp))?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Line continuation
        if ($rest =~ /^(\\)$/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # AS keyword for multi-stage builds
        if ($rest =~ /^(AS)\s+(\w+)/i) {
            push @tokens, _token($pos, $pos + 2, TOKEN_KEYWORD);
            $pos += 2;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
