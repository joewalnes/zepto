package Zepto::Syntax::KDL;
# =============================================================================
# KDL Syntax Grammar (https://kdl.dev/)
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

# Custom states
use constant STATE_ML_STRING     => 10;  # """..."""
use constant STATE_BLOCK_COMMENT => 11;  # /* ... */ (nestable, depth encoded as 11+depth-1)

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue multi-line basic string """..."""
    if ($state == STATE_ML_STRING) {
        if ($line =~ /^(.*?)"""/) {
            push @tokens, _token(0, length($1) + 3, TOKEN_STRING);
            $pos = length($1) + 3;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_ML_STRING);
        }
    }

    # Continue nested block comment /* ... */
    if ($state >= STATE_BLOCK_COMMENT) {
        my $depth = $state - STATE_BLOCK_COMMENT + 1;
        while ($pos < $len) {
            my $rest = substr($line, $pos);
            if ($rest =~ m{^\*/}) {
                $depth--;
                if ($depth == 0) {
                    push @tokens, _token(0, $pos + 2, TOKEN_COMMENT);
                    $pos += 2;
                    $state = STATE_NORMAL;
                    last;
                }
                $pos += 2;
            } elsif ($rest =~ m{^/\*}) {
                $depth++;
                $pos += 2;
            } else {
                $pos++;
            }
        }
        if ($depth > 0) {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_BLOCK_COMMENT + $depth - 1);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Skip whitespace
        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line continuation
        if ($rest =~ /^(\\)\s*$/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            last;
        }

        # Line comment //
        if ($rest =~ m{^(//.*)}) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Block comment /* ... */ (nestable)
        if ($rest =~ m{^(/\*)}) {
            my $start = $pos;
            my $depth = 1;
            $pos += 2;
            while ($pos < $len && $depth > 0) {
                my $r = substr($line, $pos);
                if ($r =~ m{^\*/}) {
                    $depth--;
                    $pos += 2;
                } elsif ($r =~ m{^/\*}) {
                    $depth++;
                    $pos += 2;
                } else {
                    $pos++;
                }
            }
            if ($depth == 0) {
                push @tokens, _token($start, $pos, TOKEN_COMMENT);
            } else {
                push @tokens, _token($start, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_BLOCK_COMMENT + $depth - 1);
            }
            next;
        }

        # Slashdash (node/arg/property comment)
        if ($rest =~ m{^(/-)\s*}) {
            push @tokens, _token($pos, $pos + 2, TOKEN_COMMENT);
            $pos += 2;
            next;
        }

        # Type annotation (type)
        if ($rest =~ /^\(([^)]+)\)/) {
            my $full = length($1) + 2;
            push @tokens, _token($pos, $pos + $full, TOKEN_TYPE);
            $pos += $full;
            next;
        }

        # Multi-line string """..."""
        if ($rest =~ /^(""")/) {
            my $after = substr($rest, 3);
            if ($after =~ /^(.*?)"""/) {
                my $total = 3 + length($1) + 3;
                push @tokens, _token($pos, $pos + $total, TOKEN_STRING);
                $pos += $total;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_ML_STRING);
            }
            next;
        }

        # Raw string #"..."# with variable # count
        if ($rest =~ /^(#+)"/) {
            my $hashes = length($1);
            my $close = '"' . ('#' x $hashes);
            my $after = substr($rest, $hashes + 1);
            if ($after =~ /^(.*?)\Q$close\E/) {
                my $total = $hashes + 1 + length($1) + length($close);
                push @tokens, _token($pos, $pos + $total, TOKEN_STRING);
                $pos += $total;
            } else {
                # Raw string doesn't close on this line - treat as string to end
                push @tokens, _token($pos, $len, TOKEN_STRING);
                last;
            }
            next;
        }

        # Quoted string "..."
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # KDL special constants: #true, #false, #null, #inf, #-inf, #nan
        if ($rest =~ /^(#(?:true|false|null|inf|nan|-inf))\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Numbers: hex, octal, binary, decimal (with underscores, scientific notation)
        if ($rest =~ /^(0x[0-9a-fA-F][0-9a-fA-F_]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^(0o[0-7][0-7_]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^(0b[01][01_]*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^([+-]?\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?[\d_]+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Semicolon (node separator)
        if ($rest =~ /^;/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos++;
            next;
        }

        # Equals (property assignment)
        if ($rest =~ /^=/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos++;
            next;
        }

        # Braces
        if ($rest =~ /^[{}]/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos++;
            next;
        }

        # Identifiers - in KDL, the first identifier on a "node line" is the node name
        # We treat identifiers before = as property keys (TOKEN_VARIABLE)
        # and bare identifiers that look like node names as TOKEN_FUNCTION
        if ($rest =~ /^([\w][\w.\-]*)/) {
            my $ident = $1;
            my $after_ident = substr($line, $pos + length($ident));
            if ($after_ident =~ /^\s*=/) {
                # Property key
                push @tokens, _token($pos, $pos + length($ident), TOKEN_VARIABLE);
            } else {
                # Node name or bare value
                push @tokens, _token($pos, $pos + length($ident), TOKEN_FUNCTION);
            }
            $pos += length($ident);
            next;
        }

        $pos++;
    }

    return (\@tokens, $state == STATE_NORMAL ? STATE_NORMAL : $state);
}

1;
