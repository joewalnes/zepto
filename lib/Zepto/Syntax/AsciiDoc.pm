package Zepto::Syntax::AsciiDoc;
# =============================================================================
# AsciiDoc Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

use constant STATE_LISTING_BLOCK  => 10;  # ---- block
use constant STATE_LITERAL_BLOCK  => 11;  # .... block
use constant STATE_COMMENT_BLOCK_AD => 12;  # //// block
use constant STATE_PASSTHROUGH    => 13;  # ++++ block
use constant STATE_SIDEBAR        => 14;  # **** block

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    return ([], STATE_NORMAL) if $len == 0;

    # Continue delimited blocks
    if ($state == STATE_LISTING_BLOCK) {
        if ($line =~ /^-{4,}\s*$/) {
            push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
            return (\@tokens, STATE_NORMAL);
        }
        push @tokens, _token(0, $len, TOKEN_FUNCTION);
        return (\@tokens, STATE_LISTING_BLOCK);
    }

    if ($state == STATE_LITERAL_BLOCK) {
        if ($line =~ /^\.{4,}\s*$/) {
            push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
            return (\@tokens, STATE_NORMAL);
        }
        push @tokens, _token(0, $len, TOKEN_FUNCTION);
        return (\@tokens, STATE_LITERAL_BLOCK);
    }

    if ($state == STATE_COMMENT_BLOCK_AD) {
        if ($line =~ /^\/{4,}\s*$/) {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_NORMAL);
        }
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_COMMENT_BLOCK_AD);
    }

    if ($state == STATE_PASSTHROUGH) {
        if ($line =~ /^\+{4,}\s*$/) {
            push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
            return (\@tokens, STATE_NORMAL);
        }
        push @tokens, _token(0, $len, TOKEN_STRING);
        return (\@tokens, STATE_PASSTHROUGH);
    }

    if ($state == STATE_SIDEBAR) {
        if ($line =~ /^\*{4,}\s*$/) {
            push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
            return (\@tokens, STATE_NORMAL);
        }
        # Normal content in sidebar
        $state = STATE_SIDEBAR;
    }

    # Section titles: = Title, == Title, === Title, etc.
    if ($line =~ /^(={1,6})(\s+)(.+)$/) {
        my @h = (undef, TOKEN_HEADING1, TOKEN_HEADING2, TOKEN_HEADING3,
                 TOKEN_HEADING4, TOKEN_HEADING5, TOKEN_HEADING6);
        my $h_tok = $h[length($1)] // TOKEN_HEADING;
        push @tokens, _token(0, length($1), TOKEN_PUNCTUATION);
        push @tokens, _token(length($1) + length($2), $len, $h_tok);
        return (\@tokens, $state);
    }

    # Block delimiters
    if ($line =~ /^(-{4,})\s*$/) {
        push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
        return (\@tokens, STATE_LISTING_BLOCK);
    }
    if ($line =~ /^(\.{4,})\s*$/) {
        push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
        return (\@tokens, STATE_LITERAL_BLOCK);
    }
    if ($line =~ /^(\/{4,})\s*$/) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_COMMENT_BLOCK_AD);
    }
    if ($line =~ /^(\+{4,})\s*$/) {
        push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
        return (\@tokens, STATE_PASSTHROUGH);
    }
    if ($line =~ /^(\*{4,})\s*$/) {
        push @tokens, _token(0, $len, TOKEN_PUNCTUATION);
        return (\@tokens, STATE_SIDEBAR);
    }

    # Line comment //
    if ($line =~ m{^(//(?!/)\s*.*)}) {
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, $state);
    }

    # Attribute definition :name: value
    if ($line =~ /^(:[\w-]+:)(.*)$/) {
        push @tokens, _token(0, length($1), TOKEN_ATTRIBUTE);
        if (length($2) > 0) {
            push @tokens, _token(length($1), $len, TOKEN_STRING);
        }
        return (\@tokens, $state);
    }

    # Block title .Title
    if ($line =~ /^(\.)(\w.*)$/) {
        push @tokens, _token(0, 1, TOKEN_PUNCTUATION);
        push @tokens, _token(1, $len, TOKEN_HEADING);
        return (\@tokens, $state);
    }

    # Block attributes [source,ruby] or [NOTE] etc.
    if ($line =~ /^(\[)([^\]]+)(\])$/) {
        push @tokens, _token(0, 1, TOKEN_PUNCTUATION);
        push @tokens, _token(1, 1 + length($2), TOKEN_ATTRIBUTE);
        push @tokens, _token(1 + length($2), $len, TOKEN_PUNCTUATION);
        return (\@tokens, $state);
    }

    # Admonition labels
    if ($line =~ /^(NOTE|TIP|IMPORTANT|WARNING|CAUTION):\s/) {
        push @tokens, _token(0, length($1), TOKEN_KEYWORD);
        push @tokens, _token(length($1), length($1) + 1, TOKEN_PUNCTUATION);
        $pos = length($1) + 1;
    }

    # Include directive
    if ($line =~ /^(include::)(.+)(\[.*\])$/) {
        push @tokens, _token(0, length($1), TOKEN_KEYWORD);
        push @tokens, _token(length($1), length($1) + length($2), TOKEN_STRING);
        push @tokens, _token(length($1) + length($2), $len, TOKEN_ATTRIBUTE);
        return (\@tokens, $state);
    }

    # Other macros: image::, link::, etc.
    if ($line =~ /^(\w+::)(.+?)(\[.*\])$/) {
        push @tokens, _token(0, length($1), TOKEN_FUNCTION);
        push @tokens, _token(length($1), length($1) + length($2), TOKEN_STRING);
        push @tokens, _token(length($1) + length($2), $len, TOKEN_ATTRIBUTE);
        return (\@tokens, $state);
    }

    # Inline content
    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Attribute reference {name}
        if ($rest =~ /^(\{[\w-]+\})/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Inline code `text` or +text+
        if ($rest =~ /^(`[^`]+`)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        if ($rest =~ /^(\+[^+]+\+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Bold **text**
        if ($rest =~ /^(\*\*[^*]+\*\*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_BOLD);
            $pos += length($1);
            next;
        }

        # Bold *text*
        if ($rest =~ /^(\*[^*]+\*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_BOLD);
            $pos += length($1);
            next;
        }

        # Italic __text__
        if ($rest =~ /^(__[^_]+__)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ITALIC);
            $pos += length($1);
            next;
        }

        # Italic _text_
        if ($rest =~ /^(_[^_\s]+_)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ITALIC);
            $pos += length($1);
            next;
        }

        # URL with link text: https://example.com[text]
        if ($rest =~ /^(https?:\/\/[^\s\[]+)(\[)([^\]]*)(\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_LINK);
            $pos += length($1);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($3), TOKEN_STRING);
            $pos += length($3);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Bare URL: https://example.com
        if ($rest =~ /^(https?:\/\/[^\s\[,;)]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_LINK);
            $pos += length($1);
            next;
        }

        # Inline macros: link:url[text], image:url[text]
        if ($rest =~ /^(\w+:)([\w.\/:-]+)(\[)([^\]]*)(\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            push @tokens, _token($pos, $pos + length($2), TOKEN_LINK);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($4), TOKEN_STRING);
            $pos += length($4);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Role-annotated marked text: [.role]#text#
        if ($rest =~ /^(\[\.)([\w-]+)(\])(#)([^#]+)(#)/) {
            my $role = $2;
            my $full_len = length($1) + length($2) + length($3) + length($4) + length($5) + length($6);
            my $text_start = $pos + length($1) + length($2) + length($3) + length($4);
            my $text_end = $text_start + length($5);
            # Punctuation for [. ]# #
            push @tokens, _token($pos, $pos + length($1), TOKEN_PUNCTUATION);
            push @tokens, _token($pos + length($1), $pos + length($1) + length($2), TOKEN_ATTRIBUTE);
            push @tokens, _token($pos + length($1) + length($2), $pos + length($1) + length($2) + length($3) + length($4), TOKEN_PUNCTUATION);
            if ($role eq 'underline') {
                push @tokens, _token($text_start, $text_end, TOKEN_UNDERLINE);
            } elsif ($role =~ /^(?:line-through|strike|del)$/) {
                push @tokens, _token($text_start, $text_end, TOKEN_STRIKETHROUGH);
            } else {
                push @tokens, _token($text_start, $text_end, TOKEN_STRING);
            }
            push @tokens, _token($text_end, $text_end + 1, TOKEN_PUNCTUATION);
            $pos += $full_len;
            next;
        }

        # Cross-reference <<anchor>>
        if ($rest =~ /^(<<[^>]+>>)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_LINK);
            $pos += length($1);
            next;
        }

        # Bullet list
        if ($pos == 0 && $rest =~ /^(\s*)([-*]+)(\s)/) {
            my $indent = length($1);
            push @tokens, _token($indent, $indent + length($2), TOKEN_KEYWORD);
            $pos = $indent + length($2) + length($3);
            next;
        }

        # Numbered list
        if ($pos == 0 && $rest =~ /^(\s*)(\.+)(\s)/) {
            my $indent = length($1);
            push @tokens, _token($indent, $indent + length($2), TOKEN_KEYWORD);
            $pos = $indent + length($2) + length($3);
            next;
        }

        $pos++;
    }

    return (\@tokens, $state);
}

1;
