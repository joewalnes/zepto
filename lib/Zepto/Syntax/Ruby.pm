package Zepto::Syntax::Ruby;
# =============================================================================
# Ruby Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '#' }

my $KEYWORDS = qr/\b(?:
    BEGIN | END | alias | and | begin | break | case | class | def |
    do | else | elsif | end | ensure | false | for | if | in |
    module | next | nil | not | or | redo | rescue | retry |
    return | self | super | then | true | undef | unless | until |
    when | while | yield
)\b/x;

my $BUILTINS = qr/\b(?:
    attr_accessor | attr_reader | attr_writer |
    private | protected | public |
    require | require_relative | include | extend | prepend |
    raise | fail | catch | throw | lambda | proc | loop
)\b/x;

sub keyword_list {
    return [
        # Keywords
        qw(BEGIN END alias and begin break case class def
           do else elsif end ensure false for if in
           module next nil not or redo rescue retry
           return self super then true undef unless until
           when while yield),
        # Builtins
        qw(attr_accessor attr_reader attr_writer
           private protected public
           require require_relative include extend prepend
           raise fail catch throw lambda proc loop),
    ];
}

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    if ($state == STATE_COMMENT_BLOCK) {
        if ($line =~ /^=end\b/) {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_NORMAL);
        }
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_COMMENT_BLOCK);
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        if ($pos == 0 && $rest =~ /^=begin\b/) {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_COMMENT_BLOCK);
        }

        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        if ($rest =~ /^("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        if ($rest =~ m{^(/(?:[^/\\]|\\.)+/)([imxo]*)}) {
            my ($regex_body, $regex_flags) = ($1, $2);  # Capture before next regex clobbers $1/$2
            my $before = $pos > 0 ? substr($line, 0, $pos) : '';
            if ($before =~ /(?:^|[=(\[{,;:!&|?]|when|if|unless|and|or|not)\s*$/) {
                push @tokens, _token($pos, $pos + length($regex_body) + length($regex_flags), TOKEN_REGEX);
                $pos += length($regex_body) + length($regex_flags);
                next;
            }
        }

        if ($rest =~ /^(:\w+[?!]?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(class|module)\s+([\w:]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:class|module)\s+([\w:]+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        if ($rest =~ /^(def)\s+(\w+[?!=]?)/) {
            push @tokens, _token($pos, $pos + 3, TOKEN_KEYWORD);
            $pos += 3;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^def\s+(\w+[?!=]?)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^($BUILTINS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\@{1,2}\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\$[\w]+|\$[!@&\`'+~=\/\\,;.<>*\$?:"0-9])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(<=>|==|!=|<=|>=|&&|\|\||=~|!~|\.\.\.?|[+\-*\/%&|^~<>=!])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\w+[?!]?)(?=\s*[({]|\s+\w)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^([A-Z][a-zA-Z0-9_]*)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
