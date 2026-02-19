package Zepto::Syntax::Logfile;
# =============================================================================
# Log File Syntax Grammar
# =============================================================================
# Highlights common log formats: syslog, Apache/Nginx access/error, generic

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

my $LOG_LEVELS = qr/\b(?:
    EMERG|EMERGENCY|ALERT|CRIT|CRITICAL|FATAL|
    ERR|ERROR|SEVERE|
    WARN|WARNING|
    NOTICE|
    INFO|
    DEBUG|TRACE|VERBOSE|FINE|FINER|FINEST
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    return ([], STATE_NORMAL) if $len == 0;

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Date/timestamp patterns
        # ISO 8601: 2024-01-15T10:30:00Z or 2024-01-15 10:30:00
        if ($rest =~ /^(\d{4}[-\/]\d{2}[-\/]\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Syslog-style date: Jan 15 10:30:00
        if ($rest =~ /^((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Apache/Nginx date in brackets: [15/Jan/2024:10:30:00 +0000]
        if ($rest =~ /^(\[\d{2}\/\w{3}\/\d{4}:\d{2}:\d{2}:\d{2}\s+[+-]\d{4}\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Bracketed timestamps [2024-01-15 10:30:00]
        if ($rest =~ /^(\[\d{4}[-\/]\d{2}[-\/]\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Log levels (color-coded by severity)
        if ($rest =~ /^($LOG_LEVELS)/) {
            my $level = $1;
            my $type;
            if ($level =~ /^(?:EMERG|EMERGENCY|ALERT|CRIT|CRITICAL|FATAL)$/i) {
                $type = TOKEN_KEYWORD;  # Red-ish for critical
            } elsif ($level =~ /^(?:ERR|ERROR|SEVERE)$/i) {
                $type = TOKEN_KEYWORD;
            } elsif ($level =~ /^(?:WARN|WARNING)$/i) {
                $type = TOKEN_CONSTANT;
            } elsif ($level =~ /^(?:NOTICE|INFO)$/i) {
                $type = TOKEN_STRING;
            } else {
                $type = TOKEN_COMMENT;
            }
            push @tokens, _token($pos, $pos + length($level), $type);
            $pos += length($level);
            next;
        }

        # Bracketed log levels [INFO], [ERROR], etc.
        if ($rest =~ /^(\[)(EMERG(?:ENCY)?|ALERT|CRIT(?:ICAL)?|FATAL|ERR(?:OR)?|SEVERE|WARN(?:ING)?|NOTICE|INFO|DEBUG|TRACE|VERBOSE)(\])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            my $level = $2;
            my $type;
            if ($level =~ /^(?:EMERG|EMERGENCY|ALERT|CRIT|CRITICAL|FATAL|ERR|ERROR|SEVERE)$/) {
                $type = TOKEN_KEYWORD;
            } elsif ($level =~ /^(?:WARN|WARNING)$/) {
                $type = TOKEN_CONSTANT;
            } else {
                $type = TOKEN_STRING;
            }
            push @tokens, _token($pos, $pos + length($level), $type);
            $pos += length($level);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # IP addresses (IPv4)
        if ($rest =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?::\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # HTTP methods
        if ($rest =~ /^"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|CONNECT|TRACE)\s/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_STRING);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # HTTP status codes (standalone 3-digit numbers)
        if ($rest =~ /^(\b[1-5]\d{2})\b/ && $pos > 0) {
            my $code = $1;
            my $type;
            if ($code >= 500) { $type = TOKEN_KEYWORD; }
            elsif ($code >= 400) { $type = TOKEN_CONSTANT; }
            elsif ($code >= 300) { $type = TOKEN_ATTRIBUTE; }
            elsif ($code >= 200) { $type = TOKEN_STRING; }
            else { $type = TOKEN_NUMBER; }
            push @tokens, _token($pos, $pos + length($1), $type);
            $pos += length($1);
            next;
        }

        # Quoted strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # File paths
        if ($rest =~ /^(\/[\w.\/-]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Hostnames (word.word.word)
        if ($rest =~ /^([a-zA-Z][\w-]*(?:\.[\w-]+){2,})/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Key=value pairs
        if ($rest =~ /^(\w+)(=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # Standalone numbers
        if ($rest =~ /^(\d+\.?\d*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Brackets
        if ($rest =~ /^([\[\]])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
