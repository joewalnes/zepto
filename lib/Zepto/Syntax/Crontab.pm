package Zepto::Syntax::Crontab;
# =============================================================================
# Crontab Syntax Grammar
# =============================================================================
# Highlights cron schedule expressions and commands

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

my $SPECIAL_SCHEDULES = qr/\@(?:
    reboot | yearly | annually | monthly | weekly | daily | midnight | hourly
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    return ([], STATE_NORMAL) if $len == 0;

    # Comment
    if ($line =~ /^(\s*#.*)/) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Empty/whitespace-only line
    if ($line =~ /^\s*$/) {
        return ([], STATE_NORMAL);
    }

    # Environment variable setting: VAR=value
    if ($line =~ /^(\s*)([\w]+)(=)(.*)$/) {
        my $indent = length($1);
        push @tokens, _token($indent, $indent + length($2), TOKEN_VARIABLE);
        push @tokens, _token($indent + length($2), $indent + length($2) + 1, TOKEN_OPERATOR);
        push @tokens, _token($indent + length($2) + 1, $len, TOKEN_STRING);
        return (\@tokens, STATE_NORMAL);
    }

    # Skip leading whitespace
    if ($line =~ /^(\s+)/) {
        $pos = length($1);
    }

    my $rest = substr($line, $pos);

    # Special schedule keywords (@reboot, @daily, etc.)
    if ($rest =~ /^($SPECIAL_SCHEDULES)/) {
        push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
        $pos += length($1);

        # Skip whitespace
        if ($pos < $len && substr($line, $pos) =~ /^(\s+)/) {
            $pos += length($1);
        }

        # Optional user field (in system crontab)
        # Then command
        if ($pos < $len) {
            push @tokens, _token($pos, $len, TOKEN_STRING);
        }
        return (\@tokens, STATE_NORMAL);
    }

    # Standard cron fields: min hour dom month dow
    # Each field can be: *, number, range (1-5), step (*/2), list (1,3,5), names (MON, JAN)
    my $field_count = 0;
    while ($pos < $len && $field_count < 5) {
        $rest = substr($line, $pos);

        # Skip whitespace between fields
        if ($rest =~ /^(\s+)/) {
            $pos += length($1);
            next;
        }

        # Cron field: numbers, ranges, steps, wildcards, names
        if ($rest =~ /^([0-9*,\/-]+(?:\/[0-9]+)?|(?:SUN|MON|TUE|WED|THU|FRI|SAT|JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)(?:[,-](?:SUN|MON|TUE|WED|THU|FRI|SAT|JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|[0-9]+))*)(?=\s|$)/i) {
            my $field = $1;
            my $type = ($field eq '*') ? TOKEN_OPERATOR : TOKEN_NUMBER;
            push @tokens, _token($pos, $pos + length($field), $type);
            $pos += length($field);
            $field_count++;
            next;
        }

        last;
    }

    # After 5 cron fields, rest is the command
    if ($field_count == 5 && $pos < $len) {
        # Skip whitespace before command
        if (substr($line, $pos) =~ /^(\s+)/) {
            $pos += length($1);
        }

        # Optional user field in system crontab (single word before command)
        # We'll just highlight the rest as the command string
        if ($pos < $len) {
            push @tokens, _token($pos, $len, TOKEN_STRING);
        }
    }

    return (\@tokens, STATE_NORMAL);
}

1;
