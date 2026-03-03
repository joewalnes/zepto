package Zepto::Syntax::Terraform;
# =============================================================================
# Terraform/HCL Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '#' }

my $BLOCK_TYPES = qr/\b(?:
    resource | data | provider | variable | output | locals | module |
    terraform | backend | required_providers | required_version |
    provisioner | connection | lifecycle | dynamic | content |
    moved | import | removed | check
)\b/x;

my $KEYWORDS = qr/\b(?:
    true | false | null | for | in | if | each | count | self |
    path | root | module | var | local | data
)\b/x;

my $FUNCTIONS = qr/\b(?:
    abs | ceil | floor | log | max | min | pow | signum |
    chomp | format | formatlist | indent | join | lower | regex |
    regexall | replace | split | strrev | substr | title | trim |
    trimprefix | trimsuffix | trimspace | upper |
    alltrue | anytrue | chunklist | coalesce | coalescelist | compact |
    concat | contains | distinct | element | flatten | index | keys |
    length | list | lookup | map | matchkeys | merge | one | range |
    reverse | setintersection | setproduct | setsubtract | setunion |
    slice | sort | sum | transpose | values | zipmap |
    base64decode | base64encode | base64gzip | csvdecode | jsondecode |
    jsonencode | textdecodebase64 | textencodebase64 | urlencode | yamldecode |
    yamlencode |
    abspath | dirname | pathexpand | basename | file | fileexists |
    fileset | filebase64 | templatefile |
    formatdate | timeadd | timestamp | plantimestamp |
    base64sha256 | base64sha512 | bcrypt | filebase64sha256 |
    filebase64sha512 | filemd5 | filesha1 | filesha256 | filesha512 |
    md5 | rsadecrypt | sha1 | sha256 | sha512 | uuid | uuidv5 |
    cidrhost | cidrnetmask | cidrsubnet | cidrsubnets |
    can | nonsensitive | sensitive | tobool | tolist | tomap | tonumber |
    toset | tostring | try | type
)\b/x;

my $TYPES = qr/\b(?:
    string | number | bool | list | map | set | object | tuple | any
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

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

    # Continue heredoc
    if ($state >= 100) {
        # State encodes heredoc delimiter length (100 + len)
        # For simplicity, just look for any potential end marker
        if ($line =~ /^\s*([A-Z_]+)\s*$/) {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_NORMAL);
        }
        push @tokens, _token(0, $len, TOKEN_STRING);
        return (\@tokens, $state);
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line comment
        if ($rest =~ /^(#.*|\/\/.*)/) {
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

        # Heredoc <<EOF or <<-EOF
        if ($rest =~ /^(<<-?\s*)([A-Z_]+)/) {
            my $prefix = $1;
            my $delim = $2;
            push @tokens, _token($pos, $pos + length($prefix), TOKEN_OPERATOR);
            $pos += length($prefix);
            push @tokens, _token($pos, $pos + length($delim), TOKEN_STRING);
            $pos += length($delim);
            # Check if there's content on this line after the delimiter
            $rest = substr($line, $pos);
            if ($rest =~ /^\s*$/) {
                return (\@tokens, 100 + length($delim));
            }
            next;
        }

        # Block type keyword followed by label
        if ($rest =~ /^($BLOCK_TYPES)\s+"([^"]+)"/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^"([^"]+)"/) {
                push @tokens, _token($pos, $pos + length($1) + 2, TOKEN_STRING);
                $pos += length($1) + 2;
            }
            next;
        }

        # Block type keyword
        if ($rest =~ /^($BLOCK_TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Interpolation ${...} or %{...}
        if ($rest =~ /^([\$%]\{)/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_OPERATOR);
            $pos += 2;
            next;
        }

        # String templates (detect template directives)
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Functions
        if ($rest =~ /^($FUNCTIONS)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Types
        if ($rest =~ /^($TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Variable references var.xxx, local.xxx, data.xxx, etc.
        if ($rest =~ /^(var|local|data|module|each|count|self|path)\.(\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            $rest = substr($line, $pos);
            if ($rest =~ /^(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
                $pos += length($1);
            }
            next;
        }

        # Attribute names before =
        if ($rest =~ /^([\w-]+)(\s*=)(?!=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            $rest = substr($line, $pos);
            if ($rest =~ /^(\s*)(=)/) {
                $pos += length($1);
                push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
                $pos += 1;
            }
            next;
        }

        # Numbers
        if ($rest =~ /^(\d+\.?\d*(?:e[+-]?\d+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(==|!=|>=|<=|&&|\|\||=>|\.\.\.?|[+\-*\/%<>=!?:])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Brackets
        if ($rest =~ /^([\[\]{}()])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Generic function call
        if ($rest =~ /^(\w+)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
