package Zepto::Syntax::Groovy;
# =============================================================================
# Groovy Syntax Grammar
# =============================================================================
# Also used for Gradle build files

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;  # Import TOKEN_*, STATE_*, and _token()
use strict;
use warnings;

sub line_comment_prefix { '//' }

my $KEYWORDS = qr/\b(?:
    abstract | as | assert | boolean | break | byte | case | catch |
    char | class | const | continue | def | default | do | double |
    else | enum | extends | false | final | finally | float | for |
    goto | if | implements | import | in | instanceof | int | interface |
    long | native | new | null | package | private | protected | public |
    return | short | static | strictfp | super | switch | synchronized |
    this | threadsafe | throw | throws | transient | true | try | void |
    volatile | while | trait | with
)\b/x;

my $TYPES = qr/\b(?:
    Boolean | Byte | Character | Class | Double | Float | Integer |
    Long | Number | Object | Short | String | Void |
    BigDecimal | BigInteger | Date | Calendar | TimeZone |
    List | Map | Set | Collection | Iterator | Iterable |
    Closure | GString | Range | Pattern | Matcher |
    File | InputStream | OutputStream | Reader | Writer |
    URL | URI | Socket | Properties |
    GroovyObject | MetaClass | Binding
)\b/x;

# Gradle-specific keywords
my $GRADLE_KEYWORDS = qr/\b(?:
    apply | plugin | plugins | id | version | buildscript | repositories |
    dependencies | allprojects | subprojects | task | tasks | project |
    sourceSets | configurations | artifacts | publishing | buildDir |
    rootProject | rootDir | projectDir | buildFile | gradle | settings |
    ext | extra | group | description |
    implementation | api | compileOnly | runtimeOnly | testImplementation |
    testCompileOnly | testRuntimeOnly | annotationProcessor |
    compile | runtime | testCompile | testRuntime | classpath |
    mavenCentral | mavenLocal | jcenter | google | maven | ivy | flatDir |
    from | into | include | exclude | rename | filter | expand | eachFile |
    doFirst | doLast | dependsOn | finalizedBy | mustRunAfter | shouldRunAfter |
    enabled | outputs | inputs | onlyIf | upToDateWhen
)\b/x;

my $BUILTINS = qr/\b(?:
    println | print | printf | sprintf | readLine | sleep |
    each | collect | find | findAll | every | any | inject | sum |
    sort | reverse | unique | flatten | groupBy | countBy |
    take | drop | takeWhile | dropWhile | head | tail | first | last |
    min | max | count | size | length | isEmpty | asBoolean |
    split | join | trim | toUpperCase | toLowerCase | capitalize |
    startsWith | endsWith | contains | matches | replaceAll | replace |
    tokenize | padLeft | padRight | center |
    toInteger | toLong | toDouble | toFloat | toBigDecimal | toBigInteger |
    getClass | getMetaClass | hasProperty | respondsTo | invokeMethod |
    use | mixin | category | delegate | owner | thisObject |
    sprintf | format | eachLine | getText | setText | newReader | newWriter |
    withReader | withWriter | withInputStream | withOutputStream |
    leftShift | rightShift | plus | minus | multiply | div | mod | power |
    and | or | xor | negate | bitwiseNegate
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue block comment
    if ($state == STATE_COMMENT_BLOCK) {
        if ($line =~ /^(.*?)\*\//) {
            push @tokens, _token(0, length($1) + 2, TOKEN_COMMENT);
            $pos = length($1) + 2;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_COMMENT_BLOCK);
        }
    }

    # Continue triple-quoted string
    if ($state == 10) {  # """..."""
        if ($line =~ /^(.*?)"""/) {
            push @tokens, _token(0, length($1) + 3, TOKEN_STRING);
            $pos = length($1) + 3;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, 10);
        }
    }
    if ($state == 11) {  # '''...'''
        if ($line =~ /^(.*?)'''/) {
            push @tokens, _token(0, length($1) + 3, TOKEN_STRING);
            $pos = length($1) + 3;
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, 11);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line comment
        if ($rest =~ m{^(//.*)} ) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Block comment
        if ($rest =~ m{^(/\*)}) {
            if ($rest =~ m{^(/\*.*?\*/)}) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_COMMENT_BLOCK);
            }
            next;
        }

        # Annotation
        if ($rest =~ /^(@\w+(?:\.\w+)*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_ATTRIBUTE);
            $pos += length($1);
            next;
        }

        # Triple-quoted strings
        if ($rest =~ /^(""")/) {
            my $after_open = substr($rest, 3);
            if ($after_open =~ /^(.*?)"""/) {
                my $content_len = 3 + length($1) + 3;
                push @tokens, _token($pos, $pos + $content_len, TOKEN_STRING);
                $pos += $content_len;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, 10);
            }
            next;
        }
        if ($rest =~ /^(''')/) {
            my $after_open = substr($rest, 3);
            if ($after_open =~ /^(.*?)'''/) {
                my $content_len = 3 + length($1) + 3;
                push @tokens, _token($pos, $pos + $content_len, TOKEN_STRING);
                $pos += $content_len;
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, 11);
            }
            next;
        }

        # GString (interpolated) and regular strings
        if ($rest =~ /^("(?:[^"\\$]|\\.|\$\w+|\$\{[^}]*\})*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }
        if ($rest =~ /^('(?:[^'\\]|\\.)*')/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Slashy string (regex)
        if ($rest =~ m{^(/(?:[^/\\]|\\.)+/)}) {
            my $potential = $1;
            my $before = $pos > 0 ? substr($line, 0, $pos) : '';
            # Only treat as regex if preceded by operator or keyword
            if ($before =~ /(?:^|[=(\[{,;:!&|?~]|if|while|for|switch|case|return)\s*$/) {
                push @tokens, _token($pos, $pos + length($potential), TOKEN_REGEX);
                $pos += length($potential);
                next;
            }
        }

        # def/class/trait/interface/enum declaration
        if ($rest =~ /^(def)\s+(\w+)/) {
            push @tokens, _token($pos, $pos + 3, TOKEN_KEYWORD);
            $pos += 3;
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^(\w+)\s*\(/) {
                # Function definition
                push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
                $pos += length($1);
            } elsif ($rest =~ /^(\w+)/) {
                # Variable definition
                push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
                $pos += length($1);
            }
            next;
        }

        if ($rest =~ /^(class|trait|interface|enum)\s+(\w+)/) {
            my $kw = $1;
            push @tokens, _token($pos, $pos + length($kw), TOKEN_KEYWORD);
            $pos += length($kw);
            while ($pos < $len && substr($line, $pos, 1) =~ /\s/) { $pos++; }
            $rest = substr($line, $pos);
            if ($rest =~ /^(\w+)/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
                $pos += length($1);
            }
            next;
        }

        # Gradle keywords
        if ($rest =~ /^($GRADLE_KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Keywords
        if ($rest =~ /^($KEYWORDS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # Built-in types
        if ($rest =~ /^($TYPES)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        # Built-in functions
        if ($rest =~ /^($BUILTINS)(?=\s*[({])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(0x[0-9a-fA-F_]+[gGlL]?|0b[01_]+[gGlL]?|\d[\d_]*\.?[\d_]*(?:e[+-]?[\d_]+)?[gGlLfFdD]?)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Operators
        if ($rest =~ /^(\.\.<?|\*\.|\.&|<=>|=~|==~|\?\.|<<?|>>?>?|&&|\|\||[+\-*\/%&|^~<>=!]=?|::)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_OPERATOR);
            $pos += length($1);
            next;
        }

        # Method call or closure
        if ($rest =~ /^(\w+)(?=\s*[({])/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # CONSTANT_NAME
        if ($rest =~ /^([A-Z][A-Z0-9_]+)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Type name (PascalCase)
        if ($rest =~ /^([A-Z][a-zA-Z0-9]*)\b/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_TYPE);
            $pos += length($1);
            next;
        }

        $pos++;
    }

    return (\@tokens, STATE_NORMAL);
}

1;
