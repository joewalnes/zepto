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

# Zepto::Syntax::CSS and Zepto::Syntax::TypeScript are used for embedded
# highlighting. They're not loaded here because in the single-file bundle
# all packages are already available. They're instantiated lazily below.

# Multi-line states
use constant STATE_COMMENT     => 20;  # Inside <!-- -->

# Embedded language states: base + sub-grammar state
# Script states (base 30)
use constant STATE_SCRIPT_BASE => 30;
# Style states (base 40)
use constant STATE_STYLE_BASE  => 40;

# For backwards compat, keep old names pointing to base states
use constant STATE_SCRIPT      => 30;
use constant STATE_STYLE       => 40;

sub _css_grammar {
    my ($self) = @_;
    unless ($self->{_css_grammar}) {
        eval "require Zepto::Syntax::CSS" unless Zepto::Syntax::CSS->can('new');
        $self->{_css_grammar} = Zepto::Syntax::CSS->new();
    }
    $self->{_css_grammar};
}

sub _js_grammar {
    my ($self) = @_;
    unless ($self->{_js_grammar}) {
        eval "require Zepto::Syntax::TypeScript" unless Zepto::Syntax::TypeScript->can('new');
        $self->{_js_grammar} = Zepto::Syntax::TypeScript->new();
    }
    $self->{_js_grammar};
}

# Delegate tokenization to an embedded grammar.
# Returns ($tokens_ref, $new_pos, $new_html_state)
sub _delegate_embedded {
    my ($self, $line, $pos, $close_re, $grammar, $state_base, $sub_state) = @_;
    my @tokens;
    my $rest = substr($line, $pos);

    if ($rest =~ /$close_re/) {
        my $tag_start = $-[0];
        my $tag_end = $+[0];
        # Tokenize content before closing tag with sub-grammar
        if ($tag_start > 0) {
            my $content = substr($rest, 0, $tag_start);
            my ($sub_tokens) = $grammar->tokenize($content, $sub_state);
            # Offset token positions
            for my $tok (@$sub_tokens) {
                push @tokens, _token($pos + $tok->{start}, $pos + $tok->{end}, $tok->{type});
            }
        }
        # The closing tag
        push @tokens, _token($pos + $tag_start, $pos + $tag_end, TOKEN_TAG);
        return (\@tokens, $pos + $tag_end, STATE_NORMAL);
    } else {
        # Entire line is embedded content
        my $content = substr($line, $pos);
        my ($sub_tokens, $new_sub_state) = $grammar->tokenize($content, $sub_state);
        for my $tok (@$sub_tokens) {
            push @tokens, _token($pos + $tok->{start}, $pos + $tok->{end}, $tok->{type});
        }
        return (\@tokens, length($line), $state_base + $new_sub_state);
    }
}

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    return ([], $state // STATE_NORMAL) if $len == 0;

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

    # Handle multi-line script state - delegate to JS grammar
    if ($state >= STATE_SCRIPT_BASE && $state < STATE_STYLE_BASE) {
        my $sub_state = $state - STATE_SCRIPT_BASE;
        my ($sub_tokens, $new_pos, $new_state) =
            $self->_delegate_embedded($line, 0, qr/<\/script\s*>/i,
                                       $self->_js_grammar, STATE_SCRIPT_BASE, $sub_state);
        push @tokens, @$sub_tokens;
        $pos = $new_pos;
        $state = $new_state;
        if ($state >= STATE_SCRIPT_BASE) {
            return (\@tokens, $state);
        }
    }

    # Handle multi-line style state - delegate to CSS grammar
    if ($state >= STATE_STYLE_BASE) {
        my $sub_state = $state - STATE_STYLE_BASE;
        my ($sub_tokens, $new_pos, $new_state) =
            $self->_delegate_embedded($line, 0, qr/<\/style\s*>/i,
                                       $self->_css_grammar, STATE_STYLE_BASE, $sub_state);
        push @tokens, @$sub_tokens;
        $pos = $new_pos;
        $state = $new_state;
        if ($state >= STATE_STYLE_BASE) {
            return (\@tokens, $state);
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
            # Delegate remaining content to JS grammar
            my ($sub_tokens, $new_pos, $new_state) =
                $self->_delegate_embedded($line, $pos, qr/<\/script\s*>/i,
                                           $self->_js_grammar, STATE_SCRIPT_BASE, STATE_NORMAL);
            push @tokens, @$sub_tokens;
            $pos = $new_pos;
            $state = $new_state;
            if ($state >= STATE_SCRIPT_BASE) {
                return (\@tokens, $state);
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
            # Delegate remaining content to CSS grammar
            my ($sub_tokens, $new_pos, $new_state) =
                $self->_delegate_embedded($line, $pos, qr/<\/style\s*>/i,
                                           $self->_css_grammar, STATE_STYLE_BASE, STATE_NORMAL);
            push @tokens, @$sub_tokens;
            $pos = $new_pos;
            $state = $new_state;
            if ($state >= STATE_STYLE_BASE) {
                return (\@tokens, $state);
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
