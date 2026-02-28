package Zepto::Syntax::ReStructuredText;
# =============================================================================
# reStructuredText Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

use constant STATE_CODE_BLOCK    => 10;
use constant STATE_LITERAL_BLOCK => 11;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    return ([], STATE_NORMAL) if $len == 0;

    # Continue code block (indented after :: or directive)
    if ($state == STATE_CODE_BLOCK || $state == STATE_LITERAL_BLOCK) {
        # Code blocks end when indentation returns to original level
        if ($line =~ /^(\s+)/) {
            push @tokens, _token(0, $len, TOKEN_FUNCTION);
            return (\@tokens, $state);
        } elsif ($line =~ /^\s*$/) {
            # Empty line could still be in code block
            return ([], $state);
        } else {
            # Back to normal text
            $state = STATE_NORMAL;
        }
    }

    # Section titles (underline/overline with = - ` : . ' " ~ ^ _ * + #)
    if ($line =~ /^([=\-`:.'"~^_*+#])\1{2,}\s*$/) {
        push @tokens, _token(0, $len, TOKEN_HEADING);
        return (\@tokens, STATE_NORMAL);
    }

    # Directive: .. directive:: argument
    if ($line =~ /^(\.\.\s+)([\w:-]+)(::)(.*)$/) {
        my $dots_len = length($1);
        my $name = $2;
        my $colons_start = $dots_len + length($name);

        push @tokens, _token(0, $dots_len, TOKEN_PUNCTUATION);
        push @tokens, _token($dots_len, $colons_start, TOKEN_KEYWORD);
        push @tokens, _token($colons_start, $colons_start + 2, TOKEN_PUNCTUATION);
        if (length($4) > 0) {
            push @tokens, _token($colons_start + 2, $len, TOKEN_STRING);
        }

        # code-block, sourcecode, literalinclude start code state
        if ($name =~ /^(?:code-block|sourcecode|literalinclude|code|highlight|parsed-literal)$/) {
            return (\@tokens, STATE_CODE_BLOCK);
        }
        return (\@tokens, STATE_NORMAL);
    }

    # Comment: .. (with nothing following, or text on next indented line)
    if ($line =~ /^(\.\.\s*)$/) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Comment line (.. followed by text that's not a directive)
    if ($line =~ /^(\.\.\s+)(?![\w:-]+::)(.*)$/) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_NORMAL);
    }

    # Line ending with :: starts a literal block
    if ($line =~ /::\s*$/) {
        # Tokenize the line normally, but return code state
        # The :: at the end is special
        if ($line =~ /^(.+?)(::)\s*$/) {
            push @tokens, _token(0, length($1), TOKEN_HEADING);
            push @tokens, _token(length($1), length($1) + 2, TOKEN_PUNCTUATION);
            return (\@tokens, STATE_LITERAL_BLOCK);
        }
    }

    # Field list :field: value
    if ($line =~ /^(\s*)(:[\w\s-]+:)(.*)$/) {
        my $indent = length($1);
        push @tokens, _token($indent, $indent + length($2), TOKEN_ATTRIBUTE);
        if (length($3) > 0) {
            push @tokens, _token($indent + length($2), $len, TOKEN_STRING);
        }
        return (\@tokens, STATE_NORMAL);
    }

    # Role :role:`text`
    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Inline role :role:`text`
        if ($rest =~ /^(:[\w-]+:)(`[^`]+`)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            push @tokens, _token($pos, $pos + length($2), TOKEN_STRING);
            $pos += length($2);
            next;
        }

        # Interpreted text `text`
        if ($rest =~ /^(``[^`]+``)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Hyperlink reference `text <url>`_ (must check before plain interpreted text)
        if ($rest =~ /^(`[^`]+`_)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_LINK);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(`[^`]+`)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Strong emphasis **text**
        if ($rest =~ /^(\*\*[^*]+\*\*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_BOLD);
            $pos += length($1);
            next;
        }

        # Emphasis *text*
        if ($rest =~ /^(\*[^*]+\*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ITALIC);
            $pos += length($1);
            next;
        }

        # Footnote/citation reference [#]_ or [*]_ or [name]_
        if ($rest =~ /^(\[(?:#?\w*|\*)\]_)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_LINK);
            $pos += length($1);
            next;
        }

        # Substitution |text| (no spaces — avoids matching table cell delimiters)
        if ($rest =~ /^(\|[\w-]+\|)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Bullet list
        if ($pos == 0 && $rest =~ /^(\s*)([-*+])(\s)/) {
            my $indent = length($1);
            push @tokens, _token($indent, $indent + 1, TOKEN_KEYWORD);
            $pos = $indent + 1 + length($3);
            next;
        }

        # Numbered list
        if ($pos == 0 && $rest =~ /^(\s*)(\d+\.|#\.)(\s)/) {
            my $indent = length($1);
            push @tokens, _token($indent, $indent + length($2), TOKEN_KEYWORD);
            $pos = $indent + length($2) + length($3);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
