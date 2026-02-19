package Zepto::Syntax::R;
# =============================================================================
# R Language Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

my $KEYWORDS = qr/\b(?:
    if | else | for | while | repeat | in | next | break |
    function | return | switch |
    TRUE | FALSE | NULL | NA | NA_integer_ | NA_real_ | NA_complex_ | NA_character_ |
    Inf | NaN | library | require | source | setwd
)\b/x;

my $BUILTINS = qr/\b(?:
    c | list | vector | matrix | array | data\.frame | factor |
    length | nrow | ncol | dim | names | colnames | rownames |
    seq | rep | seq_len | seq_along |
    paste | paste0 | sprintf | format | nchar | substr | substring |
    grep | grepl | sub | gsub | regexpr | gregexpr | regmatches |
    strsplit | trimws | toupper | tolower |
    print | cat | message | warning | stop | tryCatch | withCallingHandlers |
    sum | prod | mean | median | var | sd | min | max | range | cumsum |
    abs | sqrt | log | log2 | log10 | exp | ceiling | floor | round | trunc |
    sin | cos | tan | asin | acos | atan | atan2 |
    sort | order | rank | rev | unique | duplicated | table | which |
    match | pmatch | charmatch |
    is\.null | is\.na | is\.numeric | is\.character | is\.logical | is\.list |
    is\.vector | is\.matrix | is\.data\.frame | is\.function |
    as\.numeric | as\.character | as\.logical | as\.integer | as\.double |
    as\.factor | as\.matrix | as\.data\.frame | as\.list |
    ifelse | do\.call | lapply | sapply | vapply | tapply | mapply | apply |
    Map | Reduce | Filter | Find | Position |
    tryCatch | try | on\.exit | sys\.call | sys\.function |
    environment | new\.env | parent\.env | globalenv | baseenv | emptyenv |
    assign | get | exists | rm | ls |
    file\.path | file\.exists | dir\.create | dir\.exists |
    read\.csv | read\.table | write\.csv | write\.table |
    readLines | writeLines | readRDS | saveRDS |
    Sys\.time | Sys\.sleep | proc\.time | system\.time |
    class | inherits | methods | setClass | setGeneric | setMethod |
    attr | attributes | structure |
    nargs | missing | match\.arg | on\.exit |
    identical | all\.equal | setdiff | intersect | union
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue multi-line string
    if ($state == STATE_STRING_DOUBLE) {
        if ($line =~ /^(.*?)(?<!\\)"/) {
            push @tokens, _token(0, length($1) + 1, TOKEN_STRING);
            $pos = length($1) + 1;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_STRING_DOUBLE);
        }
    }

    if ($state == STATE_STRING_SINGLE) {
        if ($line =~ /^(.*?)(?<!\\)'/) {
            push @tokens, _token(0, length($1) + 1, TOKEN_STRING);
            $pos = length($1) + 1;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_STRING_SINGLE);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Comment
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Raw strings R"(...)" or r"(...)"
        if ($rest =~ /^([rR]"[({](?:[^)}])*[)}]")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Double-quoted string
        if ($rest =~ /^"/) {
            if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_DOUBLE);
            }
            next;
        }

        # Single-quoted string
        if ($rest =~ /^'/) {
            if ($rest =~ /^('(?:[^'\\]|\\.)*')/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_STRING_SINGLE);
            }
            next;
        }

        # Backtick-quoted names
        if ($rest =~ /^(`[^`]*`)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Builtin functions
        if ($rest =~ /^($BUILTINS)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Function call
        if ($rest =~ /^([\w.]+)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers (including scientific notation and complex)
        if ($rest =~ /^(0x[0-9a-fA-F]+L?|\d+\.?\d*(?:e[+-]?\d+)?[Li]?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Special operators
        if ($rest =~ /^(%[^%]*%)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Pipe operator |> and magrittr pipe %>%
        if ($rest =~ /^(\|>|%>%)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Assignment operators
        if ($rest =~ /^(<-|<<-|->|->>|=)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Comparison and other operators
        if ($rest =~ /^(>=|<=|==|!=|&&|\|\||&|\||!|\+|-|\*|\/|\^|~|:|\$|\@)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Formula operator ~
        if ($rest =~ /^(~)/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # Punctuation
        if ($rest =~ /^([{}()\[\],;])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, $state);
}

1;
