package Zepto::Syntax::Perl;
# =============================================================================
# Perl Syntax Grammar
# =============================================================================
#
# Highlights: keywords, strings, comments, POD, variables, regex, numbers
#
# Perl is notoriously hard to parse correctly (only perl can parse Perl),
# but we can get good results for common patterns.
#
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

# Keywords (control flow, declarations)
my $KEYWORDS = qr/\b(?:
    sub | my | our | local | state |
    use | require | no | package |
    if | elsif | else | unless |
    while | until | for | foreach | loop |
    given | when | default |
    return | last | next | redo | goto |
    do | eval |
    and | or | not | xor |
    eq | ne | lt | gt | le | ge | cmp |
    BEGIN | END | CHECK | INIT | UNITCHECK |
    __END__ | __DATA__ | __FILE__ | __LINE__ | __PACKAGE__
)\b/x;

# Built-in functions
my $BUILTINS = qr/\b(?:
    abs | accept | alarm | atan2 | bind | binmode | bless |
    caller | chdir | chmod | chomp | chop | chown | chr | chroot | close | closedir |
    connect | cos | crypt |
    dbmclose | dbmopen | defined | delete | die | dump |
    each | endgrent | endhostent | endnetent | endprotoent | endpwent | endservent |
    eof | eval | exec | exists | exit | exp |
    fcntl | fileno | flock | fork | format | formline |
    getc | getgrent | getgrgid | getgrnam | gethostbyaddr | gethostbyname | gethostent |
    getlogin | getnetbyaddr | getnetbyname | getnetent | getpeername | getpgrp | getppid |
    getpriority | getprotobyname | getprotobynumber | getprotoent | getpwent | getpwnam |
    getpwuid | getservbyname | getservbyport | getservent | getsockname | getsockopt | glob | gmtime | grep | goto |
    hex |
    import | index | int | ioctl |
    join | keys | kill |
    last | lc | lcfirst | length | link | listen | local | localtime | log | lstat |
    map | mkdir | msgctl | msgget | msgrcv | msgsnd |
    next |
    oct | open | opendir | ord |
    pack | pipe | pop | pos | print | printf | prototype | push |
    quotemeta |
    rand | read | readdir | readline | readlink | readpipe | recv | redo | ref | rename |
    reset | return | reverse | rewinddir | rindex | rmdir |
    say | scalar | seek | seekdir | select | semctl | semget | semop | send | setgrent |
    sethostent | setnetent | setpgrp | setpriority | setprotoent | setpwent | setservent |
    setsockopt | shift | shmctl | shmget | shmread | shmwrite | shutdown | sin | sleep |
    socket | socketpair | sort | splice | split | sprintf | sqrt | srand | stat | study |
    substr | symlink | syscall | sysopen | sysread | sysseek | system | syswrite |
    tell | telldir | tie | tied | time | times | truncate |
    uc | ucfirst | umask | undef | unlink | unpack | unshift | untie | utime |
    values | vec |
    wait | waitpid | wantarray | warn | write
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue POD documentation
    if ($state == STATE_POD) {
        if ($line =~ /^=cut\b/) {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_NORMAL);
        }
        push @tokens, _token(0, $len, TOKEN_COMMENT);
        return (\@tokens, STATE_POD);
    }

    # Continue multi-line string (heredoc would need more complex tracking)
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

        # POD documentation start (must be at line start)
        if ($pos == 0 && $rest =~ /^(=[a-zA-Z]\w*)/) {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_POD);
        }

        # Skip whitespace
        if ($rest =~ /^(\s+)/) {
            $pos += length($1);
            next;
        }

        # Line comment
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Double-quoted string
        if ($rest =~ /^"/) {
            if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                # Unclosed string - extends to end of line
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

        # Backtick command
        if ($rest =~ /^(`(?:[^`\\]|\\.)*`)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # q/qq/qw/qx/qr quoting
        if ($rest =~ /^(q[qwxr]?)(\s*)(\S)/) {
            my $op = $1;
            my $space = $2;
            my $delim = $3;
            my $close_delim = $delim;
            $close_delim = ')' if $delim eq '(';
            $close_delim = ']' if $delim eq '[';
            $close_delim = '}' if $delim eq '{';
            $close_delim = '>' if $delim eq '<';

            # Simple case: single char delimiters with no nesting
            my $escaped_close = quotemeta($close_delim);
            if ($rest =~ /^(q[qwxr]?\s*\Q$delim\E(?:[^\\$escaped_close]|\\.)*\Q$close_delim\E)/) {
                my $token_type = ($op eq 'qr') ? TOKEN_REGEX : TOKEN_STRING;
                push @tokens, _token($pos, $pos + length($1), $token_type);
                $pos += length($1);
                next;
            }
        }

        # Substitution s///, transliteration tr///, y///
        # Must come before regex match to avoid partial matching
        if ($rest =~ m{^((s|tr|y)\s*/(?:[^/\\]|\\.)*/((?:[^/\\]|\\.)*)/)([msixpodualngcer]*)}) {
            push @tokens, _token($pos, $pos + length($1) + length($4), TOKEN_REGEX);
            $pos += length($1) + length($4);
            next;
        }

        # Regex match m// or bare //
        # m// is explicit, bare // is matched here too (may sometimes match division, but that's rare)
        if ($rest =~ m{^(m\s*/(?:[^/\\]|\\.)*/)([msixpodualngc]*)}) {
            push @tokens, _token($pos, $pos + length($1) + length($2), TOKEN_REGEX);
            $pos += length($1) + length($2);
            next;
        }

        # Bare /regex/ - only if it looks like a regex (has content and closing /)
        if ($rest =~ m{^(/(?:[^/\\]|\\.)+/)([msixpodualngc]*)}) {
            push @tokens, _token($pos, $pos + length($1) + length($2), TOKEN_REGEX);
            $pos += length($1) + length($2);
            next;
        }

        # Subroutine definition: sub name
        if ($rest =~ /^(sub\s+)(\w+)/) {
            push @tokens, _token($pos, $pos + length($1) - 1, TOKEN_KEYWORD);
            $pos += length($1);
            # Skip any whitespace that was captured
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^sub\s+(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            }
            next;
        }

        # Package declaration
        if ($rest =~ /^(package\s+)([\w:]+)/) {
            push @tokens, _token($pos, $pos + length($1) - 1, TOKEN_KEYWORD);
            $pos += length($1);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^package\s+([\w:]+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        # Use/require with module name
        if ($rest =~ /^(use|require|no)\s+([\w:]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1) + 1;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            if ($rest =~ /^(?:use|require|no)\s+([\w:]+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        # Keywords (only match at actual word boundary - not mid-word)
        if ($rest =~ /^($KEYWORDS)/) {
            # Check that we're not in the middle of a word
            my $prev_char = $pos > 0 ? substr($line, $pos - 1, 1) : '';
            if ($prev_char !~ /\w/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
                $pos += length($1);
                next;
            }
        }

        # Built-in functions (only match at actual word boundary)
        if ($rest =~ /^($BUILTINS)/) {
            my $prev_char = $pos > 0 ? substr($line, $pos - 1, 1) : '';
            if ($prev_char !~ /\w/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
                next;
            }
        }

        # Special variables $1, $&, $', etc.
        if ($rest =~ /^(\$(?:[0-9]+|[&\`'+]|{\^[A-Z]+}))/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Variables: $foo, @bar, %baz, $foo{key}, $foo[0]
        if ($rest =~ /^([\$\@\%][\w]+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Sigils with braces: ${foo}, @{$arrayref}
        if ($rest =~ /^([\$\@\%]\{)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F_]+|0b[01_]+|0[0-7_]+|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Arrow operator
        if ($rest =~ /^(->)/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_OPERATOR);
            $pos += 2;
            next;
        }

        # Fat comma
        if ($rest =~ /^(=>)/) {
            push @tokens, _token($pos, $pos + 2, TOKEN_OPERATOR);
            $pos += 2;
            next;
        }

        # Other operators
        if ($rest =~ /^(=~|!~|<=>|<>|&&|\|\||\/\/|\.\.\.?|[+\-*\/%&|^~<>=!.x])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Method/function call: ->method or function(
        if ($rest =~ /^(\w+)(?=\s*\()/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Bareword after -> is a method
        if ($pos > 0 && substr($line, $pos - 2, 2) eq '->' && $rest =~ /^(\w+)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # CONSTANT_NAMES (all caps)
        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Skip other characters
        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
