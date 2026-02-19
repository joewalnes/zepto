package Zepto::Syntax::Clojure;
# =============================================================================
# Clojure/Lisp/Scheme Syntax Grammar
# =============================================================================
# This grammar handles S-expression based languages:
# - Clojure (.clj, .cljs, .cljc, .edn)
# - Common Lisp (.lisp, .cl, .lsp)
# - Scheme (.scm, .ss, .rkt)
# - Racket (.rkt)
# - Emacs Lisp (.el)

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

# Clojure special forms and keywords
my $SPECIAL_FORMS = qr/\b(?:
    def | defn | defn- | defmacro | defmethod | defmulti | defonce |
    defprotocol | defrecord | defstruct | deftype | definterface |
    fn | if | if-let | if-not | if-some | when | when-let | when-not |
    when-first | when-some | cond | condp | case | do | let | letfn |
    loop | recur | throw | try | catch | finally | monitor-enter |
    monitor-exit | new | quote | var | set! | import | ns | in-ns |
    refer | refer-clojure | require | use | load | load-file |
    comment | declare | binding | with-local-vars | with-open |
    with-bindings | with-redefs | doto | -> | ->> | as-> | some-> |
    some->> | cond-> | cond->> | and | or | not | nil | true | false
)\b/x;

# Common Lisp/Scheme special forms
my $LISP_KEYWORDS = qr/\b(?:
    lambda | define | define-syntax | let | let\* | letrec | letrec\* |
    if | cond | case | else | begin | do | set! | quote | quasiquote |
    unquote | unquote-splicing | syntax-rules | syntax-case | with-syntax |
    defun | defvar | defparameter | defconstant | defmacro | defstruct |
    defclass | defgeneric | defmethod | setq | setf | progn | prog1 |
    prog2 | block | return-from | tagbody | go | catch | throw |
    unwind-protect | multiple-value-bind | values | call-with-values |
    call\/cc | call-with-current-continuation | dynamic-wind
)\b/x;

# Common built-in functions
my $BUILTINS = qr/\b(?:
    car | cdr | cons | list | append | reverse | length | member | assoc |
    map | mapcar | mapc | maplist | filter | remove | remove-if | reduce |
    fold | foldl | foldr | apply | funcall | eval | read | print | write |
    display | newline | format | string | symbol | number | char |
    eq | eql | equal | equalp | = | < | > | <= | >= | \+ | \- | \* | \/ |
    mod | rem | abs | min | max | gcd | lcm | sqrt | expt | log | exp |
    sin | cos | tan | asin | acos | atan | floor | ceiling | truncate |
    round | random | not | and | or | null | atom | listp | numberp |
    symbolp | stringp | consp | zerop | plusp | minusp | oddp | evenp |
    first | second | third | fourth | fifth | rest | last | nth | nthcdr |
    butlast | take | drop | take-while | drop-while | partition |
    sort | stable-sort | merge | count | position | find | find-if |
    every | some | notany | notevery | all | any | none |
    str | subs | get | assoc-in | update-in | get-in | conj | into |
    concat | flatten | distinct | group-by | frequencies | interleave |
    interpose | zipmap | keys | vals | merge | merge-with |
    comp | partial | juxt | identity | constantly | complement |
    atom | deref | reset! | swap! | compare-and-set! |
    agent | send | send-off | await | ref | dosync | alter | commute |
    future | promise | deliver | realized? |
    pr | prn | print | println | pr-str | prn-str | read-string |
    slurp | spit | line-seq | file-seq
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

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line comment
        if ($rest =~ /^(;.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Clojure-style line comment #!
        if ($rest =~ /^(#!.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Discard macro #_
        if ($rest =~ /^(#_)/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_COMMENT);
            $pos += 2;
            next;
        }

        # Reader macro #' (var quote in Clojure)
        if ($rest =~ /^(#')/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_OPERATOR);
            $pos += 2;
            next;
        }

        # Block comment #| ... |# (Common Lisp, Scheme)
        if ($rest =~ /^(#\|.*?\|#)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            $pos += length($1);
            next;
        }

        # String
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

        # Character literal (Clojure: \a, \newline, \u0041)
        if ($rest =~ /^(\\(?:newline|space|tab|return|backspace|formfeed|u[0-9a-fA-F]{4}|.))/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Scheme/Lisp character #\x
        if ($rest =~ /^(#\\(?:newline|space|tab|return|[^\s()[\]{}]))/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Regex #"..."
        if ($rest =~ /^(#"(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_REGEX);
            $pos += length($1);
            next;
        }

        # Keyword :name or ::name (Clojure)
        if ($rest =~ /^(::?[\w+!\-*'?<>=\/.]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Symbol quote 'symbol
        if ($rest =~ /^(')/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # Syntax quote ` and unquote ~ and ~@
        if ($rest =~ /^(`|~@|~)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Metadata ^ (Clojure)
        if ($rest =~ /^(\^[\w:]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Special forms
        if ($rest =~ /^($SPECIAL_FORMS)(?=[\s()\[\]{}])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Lisp keywords
        if ($rest =~ /^($LISP_KEYWORDS)(?=[\s()\[\]{}])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Built-in functions
        if ($rest =~ /^($BUILTINS)(?=[\s()\[\]{}])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers (including ratios like 1/2)
        if ($rest =~ /^(-?(?:0x[0-9a-fA-F]+|\d+r[0-9a-zA-Z]+|\d+\/\d+|\d+\.?\d*(?:e[+-]?\d+)?[MN]?))(?=[\s()\[\]{}]|$)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Boolean literals
        if ($rest =~ /^(#t|#f|true|false|nil)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Clojure special syntax: #{set} #inst #uuid etc.
        if ($rest =~ /^(#(?:inst|uuid|queue|js|'|_)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Parentheses, brackets, braces
        if ($rest =~ /^([()\[\]{}])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        # Operators (deref @, lambda # in some lisps)
        if ($rest =~ /^([@#])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_OPERATOR);
            $pos += 1;
            next;
        }

        # Symbol (function call at start of list)
        # This is a general fallback - symbols followed by space in list position
        if ($rest =~ /^([\w+!\-*'?<>=\/.]+)/) {
            my $sym = $1;
            # Symbols starting with uppercase are often types/records
            if ($sym =~ /^[A-Z]/) {
                push @tokens, _token($pos, $pos + length($sym), TOKEN_TYPE);
            } else {
                # Keep as default (no specific token type)
            }
            $pos += length($sym);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
