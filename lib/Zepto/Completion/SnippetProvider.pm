package Zepto::Completion::SnippetProvider;
# =============================================================================
# SnippetProvider: Language-specific multi-token snippet expansions
# =============================================================================
#
# Triggers on exact keyword matches and provides multi-line snippet bodies.
# The Controller's accept() method returns a hashref with a 'body' field
# for snippets, which Editor.pm handles specially.
# =============================================================================

use strict;
use warnings;

my %SNIPPETS = (
    Python => [
        { trigger => 'if',    body => "if :\n    " },
        { trigger => 'for',   body => "for  in :\n    " },
        { trigger => 'def',   body => "def ():\n    " },
        { trigger => 'class', body => "class :\n    " },
        { trigger => 'while', body => "while :\n    " },
        { trigger => 'try',   body => "try:\n    \nexcept:\n    " },
        { trigger => 'with',  body => "with  as :\n    " },
    ],
    JavaScript => [
        { trigger => 'if',       body => "if () {\n    \n}" },
        { trigger => 'for',      body => "for (let i = 0; i < ; i++) {\n    \n}" },
        { trigger => 'while',    body => "while () {\n    \n}" },
        { trigger => 'function', body => "function () {\n    \n}" },
        { trigger => 'switch',   body => "switch () {\n    case :\n        break;\n}" },
        { trigger => 'try',      body => "try {\n    \n} catch (e) {\n    \n}" },
    ],
    TypeScript => [
        { trigger => 'if',        body => "if () {\n    \n}" },
        { trigger => 'for',       body => "for (let i = 0; i < ; i++) {\n    \n}" },
        { trigger => 'while',     body => "while () {\n    \n}" },
        { trigger => 'function',  body => "function () {\n    \n}" },
        { trigger => 'interface', body => "interface  {\n    \n}" },
        { trigger => 'try',       body => "try {\n    \n} catch (e) {\n    \n}" },
    ],
    Go => [
        { trigger => 'if',     body => "if  {\n    \n}" },
        { trigger => 'for',    body => "for  {\n    \n}" },
        { trigger => 'func',   body => "func () {\n    \n}" },
        { trigger => 'switch', body => "switch  {\ncase :\n    \n}" },
        { trigger => 'struct', body => "struct {\n    \n}" },
    ],
    Rust => [
        { trigger => 'fn',     body => "fn () {\n    \n}" },
        { trigger => 'if',     body => "if  {\n    \n}" },
        { trigger => 'for',    body => "for  in  {\n    \n}" },
        { trigger => 'match',  body => "match  {\n    _ => \n}" },
        { trigger => 'struct', body => "struct  {\n    \n}" },
        { trigger => 'impl',   body => "impl  {\n    \n}" },
    ],
    Java => [
        { trigger => 'if',     body => "if () {\n    \n}" },
        { trigger => 'for',    body => "for (int i = 0; i < ; i++) {\n    \n}" },
        { trigger => 'while',  body => "while () {\n    \n}" },
        { trigger => 'try',    body => "try {\n    \n} catch (Exception e) {\n    \n}" },
        { trigger => 'class',  body => "class  {\n    \n}" },
        { trigger => 'switch', body => "switch () {\n    case :\n        break;\n}" },
    ],
    C => [
        { trigger => 'if',     body => "if () {\n    \n}" },
        { trigger => 'for',    body => "for (int i = 0; i < ; i++) {\n    \n}" },
        { trigger => 'while',  body => "while () {\n    \n}" },
        { trigger => 'switch', body => "switch () {\n    case :\n        break;\n}" },
        { trigger => 'struct', body => "struct  {\n    \n};" },
    ],
    Cpp => [
        { trigger => 'if',     body => "if () {\n    \n}" },
        { trigger => 'for',    body => "for (int i = 0; i < ; i++) {\n    \n}" },
        { trigger => 'while',  body => "while () {\n    \n}" },
        { trigger => 'class',  body => "class  {\npublic:\n    \n};" },
        { trigger => 'try',    body => "try {\n    \n} catch (...) {\n    \n}" },
    ],
    Ruby => [
        { trigger => 'if',    body => "if \n    \nend" },
        { trigger => 'def',   body => "def \n    \nend" },
        { trigger => 'class', body => "class \n    \nend" },
        { trigger => 'do',    body => "do ||\n    \nend" },
        { trigger => 'begin', body => "begin\n    \nrescue => e\n    \nend" },
    ],
    Shell => [
        { trigger => 'if',    body => "if [ ]; then\n    \nfi" },
        { trigger => 'for',   body => "for  in ; do\n    \ndone" },
        { trigger => 'while', body => "while [ ]; do\n    \ndone" },
        { trigger => 'case',  body => "case  in\n    *)\n        ;;\nesac" },
    ],
    Perl => [
        { trigger => 'if',    body => "if () {\n    \n}" },
        { trigger => 'for',   body => "for my \$ () {\n    \n}" },
        { trigger => 'while', body => "while () {\n    \n}" },
        { trigger => 'sub',   body => "sub  {\n    my () = \@_;\n    \n}" },
        { trigger => 'eval',  body => "eval {\n    \n};\nif (\$\@) {\n    \n}" },
    ],
);

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub complete {
    my ($self, $context) = @_;

    my $prefix = $context->{prefix};
    return [] unless defined $prefix && length($prefix) >= 2;

    my $language = $context->{language} // '';

    # Get snippets for this language
    my $snippets = $SNIPPETS{$language};
    return [] unless $snippets;

    my $lc_prefix = lc($prefix);
    my @matches;

    for my $snippet (@$snippets) {
        my $trigger = $snippet->{trigger};
        my $lc_trigger = lc($trigger);

        # Prefix match against trigger
        next unless length($trigger) >= length($prefix);
        next unless index($lc_trigger, $lc_prefix) == 0;

        # Don't return exact match (handled by Controller dedup)
        next if $trigger eq $prefix;

        push @matches, {
            text  => $trigger,
            score => 90,
            kind  => 'snippet',
            body  => $snippet->{body},
        };
    }

    return \@matches;
}

1;
