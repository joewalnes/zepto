package Zepto::Syntax::Markdown;
# =============================================================================
# Markdown Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

use constant STATE_FENCED_CODE => 20;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    if ($state == STATE_FENCED_CODE) {
        if ($line =~ /^(\s*```\s*)$/) {
            push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
            return (\@tokens, STATE_NORMAL);
        }
        push @tokens, _token(0, $len, TOKEN_FUNCTION);
        return (\@tokens, STATE_FENCED_CODE);
    }

    return ([], STATE_NORMAL) if $len == 0;

    if ($line =~ /^(\s*```\s*)(\w*)/) {
        push @tokens, _token(0, length($1), TOKEN_PUNCTUATION);
        if ($2) {
            push @tokens, _token(length($1), length($1) + length($2), TOKEN_TYPE);
        }
        return (\@tokens, STATE_FENCED_CODE);
    }

    if ($line =~ /^(\s*)(#{1,6})(\s+)(.*)$/) {
        my $indent = length($1);
        my $hashes = $2;
        my @h = (undef, TOKEN_HEADING1, TOKEN_HEADING2, TOKEN_HEADING3,
                 TOKEN_HEADING4, TOKEN_HEADING5, TOKEN_HEADING6);
        my $h_tok = $h[length($hashes)] // TOKEN_HEADING;
        push @tokens, _token($indent, $indent + length($hashes), TOKEN_PUNCTUATION);
        push @tokens, _token($indent + length($hashes) + length($3), $len, $h_tok);
        return (\@tokens, STATE_NORMAL);
    }

    # Setext headings: === is h1, --- is h2
    if ($line =~ /^(\s*)(={3,})\s*$/) {
        push @tokens, _token(length($1), $len, TOKEN_HEADING1);
        return (\@tokens, STATE_NORMAL);
    }
    if ($line =~ /^(\s*)-{3,}\s*$/) {
        push @tokens, _token(length($1), $len, TOKEN_HEADING2);
        return (\@tokens, STATE_NORMAL);
    }

    if ($line =~ /^(\s*)([-*_]\s*){3,}\s*$/) {
        push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
        return (\@tokens, STATE_NORMAL);
    }

    if ($line =~ /^(\s*)(>+)/) {
        push @tokens, _token(length($1), length($1) + length($2), TOKEN_PUNCTUATION);
        $pos = length($1) + length($2);
    }

    if ($line =~ /^(\s*)([-*+])(\s+)/) {
        push @tokens, _token(length($1), length($1) + 1, TOKEN_KEYWORD);
        $pos = length($1) + 1 + length($3);
    }

    if ($line =~ /^(\s*)(\d+\.)(\s+)/) {
        push @tokens, _token(length($1), length($1) + length($2), TOKEN_KEYWORD);
        $pos = length($1) + length($2) + length($3);
    }

    if ($line =~ /^(    |\t)(.*)$/ && $pos == 0) {
        push @tokens, _token(0, $len, TOKEN_FUNCTION);
        return (\@tokens, STATE_NORMAL);
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # Backslash escape: \ before markdown delimiters (consumes full delimiter)
        if ($rest =~ /^\\(\*{1,3}|_{1,3}|~~|==|`+|[\\{}\[\]()#+\-.!])/) {
            $pos += 1 + length($1);
            next;
        }

        if ($rest =~ /^(`+)([^`]+)\1/) {
            my $full_match = $&;
            push @tokens, _token($pos, $pos + length($full_match), TOKEN_FUNCTION);
            $pos += length($full_match);
            next;
        }

        if ($rest =~ /^(\[)([^\]]+)\](\()([^)]+)(\))/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($2), TOKEN_STRING);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            push @tokens, _token($pos, $pos + length($4), TOKEN_LINK);
            $pos += length($4);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Highlighted ==text==
        if ($rest =~ /^(==)(.+?)\1/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            push @tokens, _token($pos, $pos + length($2), TOKEN_HIGHLIGHT);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            next;
        }

        # Strikethrough ~~text~~
        if ($rest =~ /^(~~)(.+?)\1/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            push @tokens, _token($pos, $pos + length($2), TOKEN_STRIKETHROUGH);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            next;
        }

        # Bold+italic ***text*** or ___text___
        # CommonMark: ___ must not be intraword (no alnum before open / after close)
        if ($rest =~ /^(\*\*\*)(.+?)\1/) {
            push @tokens, _token($pos, $pos + 3, TOKEN_PUNCTUATION);
            $pos += 3;
            push @tokens, _token($pos, $pos + length($2), TOKEN_BOLD_ITALIC);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 3, TOKEN_PUNCTUATION);
            $pos += 3;
            next;
        }
        if ($rest =~ /^(___)(.+?)\1/ && ($pos == 0 || substr($line, $pos - 1, 1) !~ /\w/) && ($pos + 3 + length($2) + 3 >= $len || substr($line, $pos + 3 + length($2) + 3, 1) !~ /\w/)) {
            push @tokens, _token($pos, $pos + 3, TOKEN_PUNCTUATION);
            $pos += 3;
            push @tokens, _token($pos, $pos + length($2), TOKEN_BOLD_ITALIC);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 3, TOKEN_PUNCTUATION);
            $pos += 3;
            next;
        }

        # Bold **text** or __text__
        # CommonMark: __ must not be intraword
        if ($rest =~ /^(\*\*)(.+?)\1/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            push @tokens, _token($pos, $pos + length($2), TOKEN_BOLD);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            next;
        }
        if ($rest =~ /^(__)(.+?)\1/ && ($pos == 0 || substr($line, $pos - 1, 1) !~ /\w/) && ($pos + 2 + length($2) + 2 >= $len || substr($line, $pos + 2 + length($2) + 2, 1) !~ /\w/)) {
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            push @tokens, _token($pos, $pos + length($2), TOKEN_BOLD);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 2, TOKEN_PUNCTUATION);
            $pos += 2;
            next;
        }

        # Italic *text* or _text_
        # CommonMark: _ must not be intraword
        if ($rest =~ /^(\*)(.+?)\1/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($2), TOKEN_ITALIC);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }
        if ($rest =~ /^(_)(.+?)\1/ && ($pos == 0 || substr($line, $pos - 1, 1) !~ /\w/) && ($pos + 1 + length($2) + 1 >= $len || substr($line, $pos + 1 + length($2) + 1, 1) !~ /\w/)) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($2), TOKEN_ITALIC);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        if ($rest =~ /^(<)(https?:\/\/[^>]+|[^@>]+@[^@>]+)(>)/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($2), TOKEN_LINK);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
