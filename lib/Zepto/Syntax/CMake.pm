package Zepto::Syntax::CMake;
# =============================================================================
# CMake Syntax Grammar
# =============================================================================

use parent 'Zepto::Syntax::Base';
use Zepto::Syntax::Base;
use strict;
use warnings;

sub line_comment_prefix { '#' }

# Custom state for bracket comment/string
use constant STATE_BRACKET_COMMENT => 10;
use constant STATE_BRACKET_STRING  => 11;

my $COMMANDS = qr/\b(?:
    add_compile_definitions | add_compile_options | add_custom_command |
    add_custom_target | add_definitions | add_dependencies | add_executable |
    add_library | add_link_options | add_subdirectory | add_test |
    cmake_minimum_required | cmake_parse_arguments | cmake_path | cmake_policy |
    configure_file | create_test_sourcelist |
    enable_language | enable_testing | execute_process | export |
    file | find_file | find_library | find_package | find_path | find_program |
    get_cmake_property | get_directory_property | get_filename_component |
    get_property | get_target_property | get_test_property |
    include | include_directories | include_guard | install |
    link_directories | link_libraries |
    mark_as_advanced | message | option |
    project | remove_definitions |
    set | set_directory_properties | set_property | set_source_files_properties |
    set_target_properties | set_tests_properties |
    source_group | string | target_compile_definitions | target_compile_features |
    target_compile_options | target_include_directories | target_link_directories |
    target_link_libraries | target_link_options | target_precompile_headers |
    target_sources | try_compile | try_run | unset
)\b/xi;

my $FLOW = qr/\b(?:
    if | elseif | else | endif |
    foreach | endforeach |
    while | endwhile |
    macro | endmacro |
    function | endfunction |
    block | endblock |
    return | break | continue
)\b/xi;

my $CONSTANTS = qr/\b(?:
    TRUE | FALSE | ON | OFF | YES | NO |
    AND | OR | NOT | COMMAND | DEFINED | POLICY |
    TARGET | TEST | EXISTS | IS_DIRECTORY | IS_ABSOLUTE |
    MATCHES | LESS | GREATER | EQUAL | STRLESS | STRGREATER | STREQUAL |
    VERSION_LESS | VERSION_GREATER | VERSION_EQUAL |
    CACHE | PARENT_SCOPE | FORCE |
    STATIC | SHARED | MODULE | OBJECT | INTERFACE | IMPORTED | ALIAS |
    PUBLIC | PRIVATE | REQUIRED | COMPONENTS | CONFIG | QUIET |
    FATAL_ERROR | SEND_ERROR | WARNING | STATUS | VERBOSE | DEBUG | TRACE |
    APPEND | PREPEND | REMOVE_ITEM | REMOVE_DUPLICATES |
    REPLACE | REGEX | MATCH | MATCHALL | TOLOWER | TOUPPER | STRIP |
    GLOB | GLOB_RECURSE | RENAME | REMOVE | MAKE_DIRECTORY |
    DESTINATION | TARGETS | FILES | DIRECTORY | PROGRAMS |
    RUNTIME | LIBRARY | ARCHIVE | FRAMEWORK | BUNDLE |
    PROPERTIES | PROPERTY | BRIEF_DOCS | FULL_DOCS
)\b/x;

sub tokenize {
    my ($self, $line, $state) = @_;
    my @tokens;
    my $pos = 0;
    my $len = length($line);

    # Continue bracket comment
    if ($state == STATE_BRACKET_COMMENT) {
        if ($line =~ /^(.*?)\](?:=*)\]/) {
            push @tokens, _token(0, length($1) + length($&) - length($1), TOKEN_COMMENT);
            $pos = length($&);
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_COMMENT);
            return (\@tokens, STATE_BRACKET_COMMENT);
        }
    }

    # Continue bracket string
    if ($state == STATE_BRACKET_STRING) {
        if ($line =~ /^(.*?)\](?:=*)\]/) {
            push @tokens, _token(0, length($&), TOKEN_STRING);
            $pos = length($&);
            $state = STATE_NORMAL;
        } else {
            push @tokens, _token(0, $len, TOKEN_STRING);
            return (\@tokens, STATE_BRACKET_STRING);
        }
    }

    while ($pos < $len) {
        my $rest = substr($line, $pos);

        if ($rest =~ /^(\s+)/) { $pos += length($1); next; }

        # Line comment
        if ($rest =~ /^(#[^[\n].*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Bracket comment #[[ ... ]]
        if ($rest =~ /^(#\[=*\[)/) {
            if ($rest =~ /^(#\[=*\[.*?\]=*\])/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_COMMENT);
                return (\@tokens, STATE_BRACKET_COMMENT);
            }
            next;
        }

        # Plain # comment (rest of line)
        if ($rest =~ /^(#.*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_COMMENT);
            last;
        }

        # Bracket string [[ ... ]]
        if ($rest =~ /^(\[=*\[)/) {
            if ($rest =~ /^(\[=*\[.*?\]=*\])/) {
                push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
                $pos += length($1);
            } else {
                push @tokens, _token($pos, $len, TOKEN_STRING);
                return (\@tokens, STATE_BRACKET_STRING);
            }
            next;
        }

        # Quoted strings
        if ($rest =~ /^("(?:[^"\\]|\\.)*")/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_STRING);
            $pos += length($1);
            next;
        }

        # Variable references ${VAR} or $ENV{VAR} or $CACHE{VAR}
        if ($rest =~ /^(\$(?:ENV|CACHE)?\{[^}]*\})/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Generator expressions $<...>
        if ($rest =~ /^(\$<[^>]*>)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_VARIABLE);
            $pos += length($1);
            next;
        }

        # Flow control
        if ($rest =~ /^($FLOW)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_KEYWORD);
            $pos += length($1);
            next;
        }

        # CMake commands (function calls)
        if ($rest =~ /^($COMMANDS)(?=\s*\()/i) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_FUNCTION);
            $pos += length($1);
            next;
        }

        # Constants and keywords
        if ($rest =~ /^($CONSTANTS)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_CONSTANT);
            $pos += length($1);
            next;
        }

        # Numbers
        if ($rest =~ /^(\d+\.?\d*)/) {
            push @tokens, _token($pos, $pos + length($1), TOKEN_NUMBER);
            $pos += length($1);
            next;
        }

        # Parentheses
        if ($rest =~ /^([()]])/) {
            push @tokens, _token($pos, $pos + 1, TOKEN_PUNCTUATION);
            $pos += 1;
            next;
        }

        $pos++;
    }

    return (\@tokens, $state);
}

1;
