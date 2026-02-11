package Zepto::Syntax::HTML;
# =============================================================================
# HTML Syntax Grammar
# =============================================================================
#
# Tokenizes HTML/XHTML documents including:
#   - Tags (opening, closing, self-closing)
#   - Attributes and values
#   - Comments (<!-- -->)
#   - DOCTYPE declarations
#   - Entities (&nbsp;)
#   - CDATA sections
#
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

# Multi-line states
use constant STATE_COMMENT     => 20;  # Inside <!-- -->
use constant STATE_SCRIPT      => 21;  # Inside <script>
use constant STATE_STYLE       => 22;  # Inside <style>

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    return ([], STATE_NORMAL) if $len == 0;

    # Handle multi-line comment state
    if ($state == STATE_COMMENT) {
        if ($line =~ /-->/) {
            my $end_pos = $-[0] + 3;
            push @tokens, _token(0, $end_pos, TOKEN_COMMENT);
            $pos = $end_pos;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_COMMENT);
        }
    }

    # Handle multi-line script state (treat as plain text for now)
    if ($state == STATE_SCRIPT) {
        if ($line =~ /<\/script\s*>/i) {
            my $tag_start = $-[0];
            my $tag_end = $+[0];
            # Text before closing tag
            if ($tag_start > 0) {
                push @tokens, _token(0, $tag_start, TOKEN_FUNCTION);
            }
            # The closing tag
            push @tokens, _token($tag_start, $tag_end, TOKEN_TAG);
            $pos = $tag_end;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_FUNCTION);
            return (\@tokens, STATE_SCRIPT);
        }
    }

    # Handle multi-line style state
    if ($state == STATE_STYLE) {
        if ($line =~ /<\/style\s*>/i) {
            my $tag_start = $-[0];
            my $tag_end = $+[0];
            # Text before closing tag
            if ($tag_start > 0) {
                push @tokens, _token(0, $tag_start, TOKEN_FUNCTION);
            }
            # The closing tag
            push @tokens, _token($tag_start, $tag_end, TOKEN_TAG);
            $pos = $tag_end;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_FUNCTION);
            return (\@tokens, STATE_STYLE);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        # HTML comment start: <!--
        if ($rest =~ /^<!--/) {
            if ($rest =~ /^<!--.*?-->/) {
                # Single-line comment
                my $match_len = length($&);
                push @tokens, _token($pos, $pos + $match_len, TOKEN_COMMENT);
                $pos += $match_len;
                next;
            } else {
                # Multi-line comment starts
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_COMMENT);
            }
        }

        # DOCTYPE declaration
        if ($rest =~ /^<!DOCTYPE\s+[^>]*>/i) {
            my $match_len = length($&);
            push @tokens, _token($pos, $pos + $match_len, TOKEN_KEYWORD);
            $pos += $match_len;
            next;
        }

        # CDATA section
        if ($rest =~ /^<!\[CDATA\[.*?\]\]>/s) {
            my $match_len = length($&);
            push @tokens, _token($pos, $pos + $match_len, TOKEN_STRING);
            $pos += $match_len;
            next;
        }

        # Script opening tag - enter script state
        if ($rest =~ /^<script(\s+[^>]*)?>/) {
            my $match_len = length($&);
            $self->_tokenize_tag($rest, $pos, \@tokens, $match_len);
            $pos += $match_len;
            # Check if it's self-closing
            if ($rest =~ /^<script[^>]*\/>/) {
                next;
            }
            # Check if closing tag is on same line
            my $after_open = substr($line, $pos);
            if ($after_open =~ /<\/script\s*>/i) {
                # Script content and closing tag on same line
                my $close_start = $-[0];
                my $close_end = $+[0];
                if ($close_start > 0) {
                    push @tokens, _token($pos, $pos + $close_start, TOKEN_FUNCTION);
                }
                push @tokens, _token($pos + $close_start, $pos + $close_end, TOKEN_TAG);
                $pos += $close_end;
            } else {
                $state = STATE_SCRIPT;
            }
            next;
        }

        # Style opening tag - enter style state
        if ($rest =~ /^<style(\s+[^>]*)?>/) {
            my $match_len = length($&);
            $self->_tokenize_tag($rest, $pos, \@tokens, $match_len);
            $pos += $match_len;
            # Check if it's self-closing
            if ($rest =~ /^<style[^>]*\/>/) {
                next;
            }
            # Check if closing tag is on same line
            my $after_open = substr($line, $pos);
            if ($after_open =~ /<\/style\s*>/i) {
                my $close_start = $-[0];
                my $close_end = $+[0];
                if ($close_start > 0) {
                    push @tokens, _token($pos, $pos + $close_start, TOKEN_FUNCTION);
                }
                push @tokens, _token($pos + $close_start, $pos + $close_end, TOKEN_TAG);
                $pos += $close_end;
            } else {
                $state = STATE_STYLE;
            }
            next;
        }

        # Self-closing tag: <tagname ... />
        if ($rest =~ /^<([a-zA-Z][a-zA-Z0-9:-]*)(\s+[^>]*)?\/>/) {
            my $full_match = $&;
            my $match_len = length($full_match);
            $self->_tokenize_tag($rest, $pos, \@tokens, $match_len);
            $pos += $match_len;
            next;
        }

        # Closing tag: </tagname>
        if ($rest =~ /^<\/([a-zA-Z][a-zA-Z0-9:-]*)\s*>/) {
            my $match_len = length($&);
            push @tokens, _token($pos, $pos + $match_len, TOKEN_TAG);
            $pos += $match_len;
            next;
        }

        # Opening tag: <tagname ...>
        if ($rest =~ /^<([a-zA-Z][a-zA-Z0-9:-]*)([^>]*)>/) {
            my $full_match = $&;
            my $match_len = length($full_match);
            $self->_tokenize_tag($rest, $pos, \@tokens, $match_len);
            $pos += $match_len;
            next;
        }

        # Entity reference: &name; or &#123; or &#xAB;
        if ($rest =~ /^&([a-zA-Z][a-zA-Z0-9]*|#[0-9]+|#x[0-9a-fA-F]+);/) {
            my $match_len = length($&);
            push @tokens, _token($pos, $pos + $match_len, TOKEN_CONSTANT);
            $pos += $match_len;
            next;
        }

        # Move to next character (plain text)
        $pos++;
    }

    return (\@tokens, $state // STATE_NORMAL);
}

# Tokenize a tag with attributes
sub _tokenize_tag {
    my ($self, $tag_text, $base_pos, $tokens, $tag_len) = @_;

    # Match the opening bracket and tag name
    if ($tag_text =~ /^(<\/?[a-zA-Z][a-zA-Z0-9:-]*)/) {
        my $tag_start = length($1);
        push @$tokens, _token($base_pos, $base_pos + $tag_start, TOKEN_TAG);

        # Now parse attributes
        my $attr_part = substr($tag_text, $tag_start, $tag_len - $tag_start);
        my $attr_pos = $tag_start;

        while ($attr_part =~ /\G\s*([a-zA-Z_:][a-zA-Z0-9_:.-]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g) {
            my $attr_name = $1;
            my $attr_value = $2 // $3 // $4;
            my $match_start = $-[0];
            my $match_end = $+[0];

            # Attribute name position
            my $name_start = $-[1];
            my $name_end = $+[1];
            push @$tokens, _token($base_pos + $attr_pos + $name_start,
                                   $base_pos + $attr_pos + $name_end,
                                   TOKEN_ATTRIBUTE);

            # Attribute value position (if present)
            if (defined $attr_value) {
                my $val_start = defined $2 ? $-[2] : (defined $3 ? $-[3] : $-[4]);
                my $val_end = defined $2 ? $+[2] : (defined $3 ? $+[3] : $+[4]);
                if (defined $val_start) {
                    # Include quotes in the string token
                    my $quote_offset = (defined $2 || defined $3) ? 1 : 0;
                    push @$tokens, _token($base_pos + $attr_pos + $val_start - $quote_offset,
                                           $base_pos + $attr_pos + $val_end + $quote_offset,
                                           TOKEN_STRING);
                }
            }
        }

        # The closing bracket(s)
        my $close_start = $tag_len - 1;
        if (substr($tag_text, $tag_len - 2, 2) eq '/>') {
            $close_start = $tag_len - 2;
        }
        push @$tokens, _token($base_pos + $close_start, $base_pos + $tag_len, TOKEN_TAG);
    }
}

1;
