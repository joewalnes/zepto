package Zepto::Syntax::LaTeX;
# =============================================================================
# LaTeX/TeX Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

use constant STATE_MATH_DISPLAY => 10;  # $$ ... $$
use constant STATE_VERBATIM     => 11;  # \begin{verbatim} ... \end{verbatim}

my $SECTIONING = qr/\\(?:
    part | chapter | section | subsection | subsubsection |
    paragraph | subparagraph
)\b/x;

my $ENVIRONMENTS = qr/\b(?:
    document | equation | align | gather | multline | split | cases |
    figure | table | tabular | array | matrix | pmatrix | bmatrix |
    enumerate | itemize | description | list |
    abstract | quote | quotation | verse | center | flushleft | flushright |
    minipage | frame | block | column | columns |
    theorem | lemma | proof | definition | example | remark | corollary |
    lstlisting | minted | verbatim | comment |
    tikzpicture | pgfscope | axis | scope
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue verbatim environment
    if ($state == STATE_VERBATIM) {
        if ($line =~ /^(.*?)(\\end\{verbatim\})/) {
            if (length($1) > 0) {
                push @tokens, _token(0, length($1), TOKEN_STRING);
            }
            push @tokens, _token(length($1), length($1) + length($2), TOKEN_KEYWORD);
            $pos = length($1) + length($2);
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_VERBATIM);
        }
    }

    # Continue display math $$ ... $$
    if ($state == STATE_MATH_DISPLAY) {
        if ($line =~ /^(.*?)\$\$/) {
            push @tokens, _token(0, length($1) + 2, TOKEN_NUMBER);
            $pos = length($1) + 2;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_NUMBER);
            return (\@tokens, STATE_MATH_DISPLAY);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Comment (% to end of line)
        if ($rest =~ /^(%.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # \begin{env} and \end{env}
        if ($rest =~ /^(\\(?:begin|end))\{(\w+)\}/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            push @tokens, _token($pos, $pos + length($2), TOKEN_TYPE);
            $pos += length($2);
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;

            # Check for verbatim
            if ($2 eq 'verbatim' && $rest =~ /^\\begin/) {
                my $remaining = substr($line, $pos);
                if (length($remaining) > 0) {
                    push @tokens, _token($pos, $len, TOKEN_STRING);
                }
                return (\@tokens, STATE_VERBATIM);
            }
            next;
        }

        # Sectioning commands
        if ($rest =~ /^($SECTIONING)(\*?)/) {
            push @tokens, _token($pos, $pos + length($1) + length($2), TOKEN_KEYWORD);
            $pos += length($1) + length($2);
            # Highlight the section title if in braces
            $rest = substr($line, $pos);
            if ($rest =~ /^(\{)([^}]*)(\})/) {
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
                push @tokens, _token($pos, $pos + length($2), TOKEN_HEADING);
                $pos += length($2);
                push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
                $pos += 1;
            }
            next;
        }

        # Common commands
        if ($rest =~ /^(\\(?:usepackage|documentclass|input|include|includegraphics|bibliography|bibliographystyle|label|ref|eqref|cite|pageref|footnote|caption|title|author|date|maketitle|tableofcontents|listoffigures|listoftables|newcommand|renewcommand|providecommand|DeclareMathOperator|newenvironment|renewenvironment|newtheorem|setlength|addtolength|setcounter|addtocounter|pagestyle|thispagestyle|pagenumbering))\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Formatting commands
        if ($rest =~ /^(\\(?:textbf|textit|textrm|textsf|texttt|textsc|textsl|textup|emph|underline|sout|uline|uuline|uwave|mbox|fbox|framebox|parbox|makebox|raisebox|scalebox|rotatebox|colorbox|fcolorbox))\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Math commands
        if ($rest =~ /^(\\(?:frac|sqrt|sum|prod|int|oint|lim|inf|sup|max|min|log|ln|exp|sin|cos|tan|cot|sec|csc|arcsin|arccos|arctan|sinh|cosh|tanh|det|gcd|binom|text|mathrm|mathbf|mathit|mathbb|mathcal|mathfrak|mathsf|boldsymbol|hat|bar|vec|dot|ddot|tilde|widetilde|overline|underline|overbrace|underbrace|left|right|big|Big|bigg|Bigg))\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Any other command (backslash + word)
        if ($rest =~ /^(\\[a-zA-Z]+\*?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Escaped special character
        if ($rest =~ /^(\\[%$&#_{}\[\]~^\\])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ESCAPE);
            $pos += length($1);
            next;
        }

        # Display math $$...$$
        if ($rest =~ /^(\$\$)/) {
            if ($rest =~ /^(\$\$.*?\$\$)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_NUMBER);
                return (\@tokens, STATE_MATH_DISPLAY);
            }
            next;
        }

        # Inline math $...$
        if ($rest =~ /^(\$(?:[^\$\\]|\\.)*\$)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # \( ... \) inline math
        if ($rest =~ /^(\\\()/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_NUMBER);
            $pos += 2;
            next;
        }

        if ($rest =~ /^(\\\))/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_NUMBER);
            $pos += 2;
            next;
        }

        # Optional arguments [...]
        if ($rest =~ /^(\[)/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        if ($rest =~ /^(\])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Braces
        if ($rest =~ /^([{}])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Numbers
        if ($rest =~ /^(\d+\.?\d*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Ampersand (table column separator)
        if ($rest =~ /^(&)/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, $state);
}

1;
