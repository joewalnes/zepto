package Zepto::Syntax::Systemd;
# =============================================================================
# systemd Unit File Syntax Grammar
# =============================================================================
# Handles .service, .timer, .socket, .mount, .target, .path, .slice, .scope

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub line_comment_prefix { '#' }

my $SECTIONS = qr/^\[(?:
    Unit | Service | Timer | Socket | Mount | Automount | Swap |
    Path | Slice | Scope | Install | Network | Address | Route |
    NetDev | Link | Match | DHCP | DHCPv4 | DHCPv6
)\]$/x;

my $BOOL_VALUES = qr/\b(?:
    true | false | yes | no | on | off
)\b/xi;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    return ([], STATE_NORMAL) if $len == 0;

    # Comment lines (# or ;)
    if ($line =~ /^(\s*[#;].*)/) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Section headers [Unit], [Service], etc.
    if ($line =~ /^(\[)(\w+)(\])/) {
        push @tokens, _token(0, 1, TOKEN_PUNCTUATION);
        push @tokens, _token(1, 1 + length($2), TOKEN_KEYWORD);
        push @tokens, _token(1 + length($2), 2 + length($2), TOKEN_PUNCTUATION);
        return (\@tokens, STATE_NORMAL);
    }

    # Key=Value pairs
    if ($line =~ /^(\w[\w.-]*)(\s*)(=)(.*)$/) {
        my $key = $1;
        my $space = $2;
        my $eq_pos = length($key) + length($space);
        my $value_start = $eq_pos + 1;
        my $value = $4;

        # Key
        push @tokens, _token(0, length($key), TOKEN_VARIABLE);

        # Equals sign
        push @tokens, _token($eq_pos, $eq_pos + 1, TOKEN_OPERATOR);

        # Tokenize value portion
        if (length($value) > 0) {
            _tokenize_value(\@tokens, $value_start, $value);
        }
    }

    return (\@tokens, STATE_NORMAL);
}

sub _tokenize_value {
    my ($tokens, $start, $value) = @_;
    my $pos = 0;
    my $len = length($value);

    while ($pos < $len) {
        my $rest = substr($value, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Inline comment after value
        if ($rest =~ /^([#;].*)/) {
            push @$tokens, _token($start + $pos, $start + $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Specifiers like %n, %N, %p, %i, %U, %h, etc.
        if ($rest =~ /^(%[nNpPiIfcrRtTuUhsSmCjJdDvVb%])/) {
            push @$tokens, _token($start + $pos, $start + $pos + 2, TOKEN_VARIABLE);
            $pos += 2;
            next;
        }

        # Environment variable references $VAR or ${VAR}
        if ($rest =~ /^(\$\{?\w+\}?)/) {
            push @$tokens, _token($start + $pos, $start + $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Boolean values
        if ($rest =~ /^(true|false|yes|no|on|off)\b/i) {
            push @$tokens, _token($start + $pos, $start + $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Numbers with optional units
        if ($rest =~ /^(\d+)(s|ms|us|min|h|d|w|M|K|G|T|%)?/) {
            push @$tokens, _token($start + $pos, $start + $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            if (defined $2) {
                push @$tokens, _token($start + $pos, $start + $pos + length($2), TOKEN_KEYWORD);
                $pos += length($2);
            }
            next;
        }

        # Paths (start with /, -, + or !)
        if ($pos == 0 && $rest =~ /^([!+-]?\/[\w.\/\-*]+)/) {
            push @$tokens, _token($start + $pos, $start + $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Known service types and other enum values
        if ($rest =~ /^(simple|exec|forking|oneshot|dbus|notify|idle|always|on-failure|on-abnormal|on-abort|on-watchdog|on-success|no)\b/) {
            push @$tokens, _token($start + $pos, $start + $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Target references like multi-user.target
        if ($rest =~ /^([\w.-]+\.(?:service|target|socket|timer|mount|path|slice|scope|device|swap|automount))\b/) {
            push @$tokens, _token($start + $pos, $start + $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        $pos++;
    }
}

1;
