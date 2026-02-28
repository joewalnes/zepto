#!/usr/bin/env perl
# =============================================================================
# Syntax Highlighter Test Suite
# =============================================================================
#
# This test file verifies syntax highlighting for all supported languages.
# Tests run without the full editor, making them fast and focused.
#
# To run: prove -v tests/highlighter.t
#
# =============================================================================

use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use Zepto::Highlighter;
use Zepto::Syntax::Base;

# =============================================================================
# Test Helpers
# =============================================================================

# Check if a token of given type exists at given position
sub has_token {
    my ($tokens, $type, $start, $end) = @_;
    for my $tok (@$tokens) {
        if ($tok->{type} eq $type && $tok->{start} == $start) {
            return 1 if !defined $end || $tok->{end} == $end;
        }
    }
    return 0;
}

# Check if any token covers a position
sub token_at {
    my ($tokens, $col) = @_;
    for my $tok (@$tokens) {
        return $tok->{type} if $col >= $tok->{start} && $col < $tok->{end};
    }
    return undef;
}

# Get all tokens of a type
sub tokens_of_type {
    my ($tokens, $type) = @_;
    return grep { $_->{type} eq $type } @$tokens;
}

# Debug: dump tokens
sub dump_tokens {
    my ($tokens, $line) = @_;
    diag "Line: $line";
    for my $tok (@$tokens) {
        my $text = substr($line, $tok->{start}, $tok->{end} - $tok->{start});
        diag sprintf("  [%d-%d] %-12s '%s'", $tok->{start}, $tok->{end}, $tok->{type}, $text);
    }
}

# =============================================================================
# Highlighter Module Tests
# =============================================================================

subtest 'Highlighter initialization' => sub {
    my $hl = Zepto::Highlighter->new();
    ok($hl, 'Highlighter created');
    ok(!$hl->has_grammar(), 'No grammar before set_file');

    $hl->set_file('test.pl');
    ok($hl->has_grammar(), 'Grammar loaded for .pl');
    is($hl->grammar_name(), 'Perl', 'Grammar name is Perl');
};

subtest 'Language detection' => sub {
    my $hl = Zepto::Highlighter->new();

    # By extension
    my @tests = (
        ['test.pl',     'Perl'],
        ['test.pm',     'Perl'],
        ['test.py',     'Python'],
        ['test.js',     'JavaScript'],
        ['test.jsx',    'JavaScript'],
        ['test.ts',     'TypeScript'],
        ['test.tsx',    'TypeScript'],
        ['test.rb',     'Ruby'],
        ['test.java',   'Java'],
        ['test.php',    'PHP'],
        ['test.sh',     'Shell'],
        ['test.bash',   'Shell'],
        ['test.md',     'Markdown'],
        ['Makefile',    'Makefile'],
        ['GNUmakefile', 'Makefile'],
        ['.bashrc',     'Shell'],
        ['.zshrc',      'Shell'],
        ['Rakefile',    'Ruby'],
        ['Gemfile',     'Ruby'],
    );

    for my $test (@tests) {
        my ($filename, $expected) = @$test;
        $hl->set_file($filename);
        is($hl->grammar_name(), $expected, "$filename -> $expected");
    }

    # Unknown extension
    $hl->set_file('test.xyz');
    ok(!$hl->has_grammar(), 'No grammar for unknown extension');
};

subtest 'State management' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    # Multi-line comment
    my ($tok1, $state1) = $hl->tokenize_line('/* start comment', 0);
    is($state1, Zepto::Syntax::Base::STATE_COMMENT_BLOCK, 'State is COMMENT_BLOCK');

    my ($tok2, $state2) = $hl->tokenize_line('   still comment */', 1);
    is($state2, Zepto::Syntax::Base::STATE_NORMAL, 'State returns to NORMAL');

    # Invalidation
    $hl->invalidate_from(0);
    # Re-tokenizing should work
    ($tok1, $state1) = $hl->tokenize_line('/* start comment', 0);
    is($state1, Zepto::Syntax::Base::STATE_COMMENT_BLOCK, 'State works after invalidation');
};

# =============================================================================
# Perl Grammar Tests
# =============================================================================

subtest 'Perl syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.pl');

    # Keywords
    my ($tokens, $state) = $hl->tokenize_line('if ($x) { return; }', 0);
    ok(has_token($tokens, 'keyword', 0), 'if is keyword');
    ok(has_token($tokens, 'keyword', 10), 'return is keyword');

    # Variables
    ($tokens) = $hl->tokenize_line('my $foo = @bar + %hash;', 0);
    ok(has_token($tokens, 'variable', 3), '$foo is variable');
    ok(has_token($tokens, 'variable', 10), '@bar is variable');
    ok(has_token($tokens, 'variable', 17), '%hash is variable');

    # Strings
    ($tokens) = $hl->tokenize_line('my $s = "hello world";', 0);
    ok(has_token($tokens, 'string', 8), 'double-quoted string');

    ($tokens) = $hl->tokenize_line("my \$s = 'hello';", 0);
    ok(has_token($tokens, 'string', 8), 'single-quoted string');

    # Comments
    ($tokens) = $hl->tokenize_line('my $x; # this is a comment', 0);
    ok(has_token($tokens, 'comment', 7), 'line comment');

    # POD
    ($tokens, $state) = $hl->tokenize_line('=head1 NAME', 0);
    ok(has_token($tokens, 'comment', 0), 'POD is comment');
    is($state, Zepto::Syntax::Base::STATE_POD, 'POD sets POD state');

    ($tokens, $state) = $hl->tokenize_line('Documentation here', 1);
    ok(has_token($tokens, 'comment', 0), 'POD continuation');

    ($tokens, $state) = $hl->tokenize_line('=cut', 2);
    is($state, Zepto::Syntax::Base::STATE_NORMAL, 'POD ends');

    # Subroutine
    ($tokens) = $hl->tokenize_line('sub foo { }', 0);
    ok(has_token($tokens, 'keyword', 0), 'sub is keyword');
    ok(has_token($tokens, 'function', 4), 'foo is function');

    # Regex
    ($tokens) = $hl->tokenize_line('$x =~ /pattern/i;', 0);
    ok(has_token($tokens, 'regex', 6), 'regex literal');

    # Numbers
    ($tokens) = $hl->tokenize_line('my $n = 42 + 0xFF + 3.14;', 0);
    ok(has_token($tokens, 'number', 8), 'decimal number');
    ok(has_token($tokens, 'number', 13), 'hex number');
    ok(has_token($tokens, 'number', 20), 'float number');

    # Use statement
    ($tokens) = $hl->tokenize_line('use strict;', 0);
    ok(has_token($tokens, 'keyword', 0), 'use is keyword');
    ok(has_token($tokens, 'type', 4), 'strict is type');
};

# =============================================================================
# Python Grammar Tests
# =============================================================================

subtest 'Python syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.py');

    # Keywords
    my ($tokens) = $hl->tokenize_line('if x is not None:', 0);
    ok(has_token($tokens, 'keyword', 0), 'if is keyword');
    ok(has_token($tokens, 'keyword', 5), 'is is keyword');
    ok(has_token($tokens, 'keyword', 8), 'not is keyword');
    ok(has_token($tokens, 'keyword', 12), 'None is keyword');

    # def/class
    ($tokens) = $hl->tokenize_line('def my_function():', 0);
    ok(has_token($tokens, 'keyword', 0), 'def is keyword');
    ok(has_token($tokens, 'function', 4), 'function name');

    ($tokens) = $hl->tokenize_line('class MyClass:', 0);
    ok(has_token($tokens, 'keyword', 0), 'class is keyword');
    ok(has_token($tokens, 'type', 6), 'class name is type');

    # Strings
    ($tokens) = $hl->tokenize_line('s = "hello"', 0);
    ok(has_token($tokens, 'string', 4), 'double-quoted string');

    # Triple-quoted strings
    my $state;
    ($tokens, $state) = $hl->tokenize_line('s = """multi', 0);
    is($state, 10, 'triple-quote starts multi-line');

    ($tokens, $state) = $hl->tokenize_line('line"""', 1);
    is($state, Zepto::Syntax::Base::STATE_NORMAL, 'triple-quote ends');

    # F-strings
    ($tokens) = $hl->tokenize_line('f"value: {x}"', 0);
    ok(has_token($tokens, 'string', 0), 'f-string');

    # Decorators
    ($tokens) = $hl->tokenize_line('@decorator', 0);
    ok(has_token($tokens, 'attribute', 0), 'decorator');

    # Comments
    ($tokens) = $hl->tokenize_line('x = 1  # comment', 0);
    ok(has_token($tokens, 'comment', 7), 'line comment');

    # self
    ($tokens) = $hl->tokenize_line('self.x = 1', 0);
    ok(has_token($tokens, 'variable', 0), 'self is variable');

    # Numbers
    ($tokens) = $hl->tokenize_line('n = 42 + 0xFF + 3.14e-2', 0);
    ok(has_token($tokens, 'number', 4), 'integer');
    ok(has_token($tokens, 'number', 9), 'hex');
    ok(has_token($tokens, 'number', 16), 'scientific');
};

# =============================================================================
# JavaScript Grammar Tests
# =============================================================================

subtest 'JavaScript syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    # Keywords
    my ($tokens) = $hl->tokenize_line('const x = async () => {};', 0);
    ok(has_token($tokens, 'keyword', 0), 'const is keyword');
    ok(has_token($tokens, 'keyword', 10), 'async is keyword');

    # Function
    ($tokens) = $hl->tokenize_line('function foo() {}', 0);
    ok(has_token($tokens, 'keyword', 0), 'function is keyword');
    ok(has_token($tokens, 'function', 9), 'foo is function');

    # Class
    ($tokens) = $hl->tokenize_line('class MyClass extends Base {}', 0);
    ok(has_token($tokens, 'keyword', 0), 'class is keyword');
    ok(has_token($tokens, 'keyword', 14), 'extends is keyword');

    # Strings
    ($tokens) = $hl->tokenize_line('let s = "hello";', 0);
    ok(has_token($tokens, 'string', 8), 'double-quoted string');

    ($tokens) = $hl->tokenize_line("let s = 'hello';", 0);
    ok(has_token($tokens, 'string', 8), 'single-quoted string');

    # Template literals
    my $state;
    ($tokens, $state) = $hl->tokenize_line('let s = `template', 0);
    is($state, Zepto::Syntax::Base::STATE_STRING_TEMPLATE, 'template literal multi-line');

    ($tokens, $state) = $hl->tokenize_line('literal`;', 1);
    is($state, Zepto::Syntax::Base::STATE_NORMAL, 'template ends');

    # Comments
    ($tokens) = $hl->tokenize_line('x = 1; // comment', 0);
    ok(has_token($tokens, 'comment', 7), 'line comment');

    ($tokens, $state) = $hl->tokenize_line('/* block', 0);
    is($state, Zepto::Syntax::Base::STATE_COMMENT_BLOCK, 'block comment');

    # Regex
    ($tokens) = $hl->tokenize_line('let r = /pattern/gi;', 0);
    ok(has_token($tokens, 'regex', 8), 'regex literal');

    # Arrow function
    ($tokens) = $hl->tokenize_line('const add = (a, b) => a + b;', 0);
    ok(has_token($tokens, 'operator', 19), 'arrow operator');

    # Constants
    ($tokens) = $hl->tokenize_line('const MAX_VALUE = 100;', 0);
    ok(has_token($tokens, 'constant', 6), 'CONSTANT_NAME');
};

# =============================================================================
# TypeScript Grammar Tests
# =============================================================================

subtest 'TypeScript syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.ts');

    # Type annotations
    my ($tokens) = $hl->tokenize_line('let x: number = 5;', 0);
    ok(has_token($tokens, 'type', 7), 'number type');

    # Interface
    ($tokens) = $hl->tokenize_line('interface IFoo {}', 0);
    ok(has_token($tokens, 'keyword', 0), 'interface is keyword');
    ok(has_token($tokens, 'type', 10), 'interface name is type');

    # Type alias
    ($tokens) = $hl->tokenize_line('type MyType = string;', 0);
    ok(has_token($tokens, 'keyword', 0), 'type is keyword');
    ok(has_token($tokens, 'type', 5), 'type name');

    # Enum
    ($tokens) = $hl->tokenize_line('enum Color { Red, Green }', 0);
    ok(has_token($tokens, 'keyword', 0), 'enum is keyword');
    ok(has_token($tokens, 'type', 5), 'enum name');

    # Decorators
    ($tokens) = $hl->tokenize_line('@Component({ })', 0);
    ok(has_token($tokens, 'attribute', 0), 'decorator');

    # Access modifiers
    ($tokens) = $hl->tokenize_line('private x: number;', 0);
    ok(has_token($tokens, 'keyword', 0), 'private is keyword');
};

# =============================================================================
# Ruby Grammar Tests
# =============================================================================

subtest 'Ruby syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.rb');

    # Keywords
    my ($tokens) = $hl->tokenize_line('if x.nil? then return end', 0);
    ok(has_token($tokens, 'keyword', 0), 'if is keyword');
    ok(has_token($tokens, 'keyword', 10), 'then is keyword');
    ok(has_token($tokens, 'keyword', 15), 'return is keyword');
    ok(has_token($tokens, 'keyword', 22), 'end is keyword');

    # def/class
    ($tokens) = $hl->tokenize_line('def my_method', 0);
    ok(has_token($tokens, 'keyword', 0), 'def is keyword');
    ok(has_token($tokens, 'function', 4), 'method name');

    ($tokens) = $hl->tokenize_line('class MyClass < Base', 0);
    ok(has_token($tokens, 'keyword', 0), 'class is keyword');
    ok(has_token($tokens, 'type', 6), 'class name');

    # Symbols
    ($tokens) = $hl->tokenize_line(':my_symbol', 0);
    ok(has_token($tokens, 'constant', 0), 'symbol');

    # Instance variables
    ($tokens) = $hl->tokenize_line('@instance_var = 1', 0);
    ok(has_token($tokens, 'variable', 0), 'instance variable');

    ($tokens) = $hl->tokenize_line('@@class_var = 1', 0);
    ok(has_token($tokens, 'variable', 0), 'class variable');

    # Global variables
    ($tokens) = $hl->tokenize_line('$global = 1', 0);
    ok(has_token($tokens, 'variable', 0), 'global variable');

    # Strings
    ($tokens) = $hl->tokenize_line('s = "hello"', 0);
    ok(has_token($tokens, 'string', 4), 'string');

    # Comments
    ($tokens) = $hl->tokenize_line('x = 1 # comment', 0);
    ok(has_token($tokens, 'comment', 6), 'comment');

    # Multi-line comment
    my $state;
    ($tokens, $state) = $hl->tokenize_line('=begin', 0);
    is($state, Zepto::Syntax::Base::STATE_COMMENT_BLOCK, 'multi-line comment');

    ($tokens, $state) = $hl->tokenize_line('=end', 1);
    is($state, Zepto::Syntax::Base::STATE_NORMAL, 'multi-line comment ends');

    # Regex
    ($tokens) = $hl->tokenize_line('r = /pattern/i', 0);
    ok(has_token($tokens, 'regex', 4), 'regex');
};

# =============================================================================
# Java Grammar Tests
# =============================================================================

subtest 'Java syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.java');

    # Keywords
    my ($tokens) = $hl->tokenize_line('public static void main(String[] args) {', 0);
    ok(has_token($tokens, 'keyword', 0), 'public is keyword');
    ok(has_token($tokens, 'keyword', 7), 'static is keyword');
    ok(has_token($tokens, 'type', 14), 'void is type');
    ok(has_token($tokens, 'function', 19), 'main is function');

    # Class
    ($tokens) = $hl->tokenize_line('class MyClass extends Base {', 0);
    ok(has_token($tokens, 'keyword', 0), 'class is keyword');
    ok(has_token($tokens, 'type', 6), 'class name');
    ok(has_token($tokens, 'keyword', 14), 'extends is keyword');

    # Annotations
    ($tokens) = $hl->tokenize_line('@Override', 0);
    ok(has_token($tokens, 'attribute', 0), 'annotation');

    # Types
    ($tokens) = $hl->tokenize_line('int x = 5;', 0);
    ok(has_token($tokens, 'type', 0), 'int is type');

    ($tokens) = $hl->tokenize_line('String s = "hello";', 0);
    ok(has_token($tokens, 'type', 0), 'String is type');

    # Comments
    ($tokens) = $hl->tokenize_line('x = 1; // comment', 0);
    ok(has_token($tokens, 'comment', 7), 'line comment');

    my $state;
    ($tokens, $state) = $hl->tokenize_line('/** Javadoc', 0);
    is($state, Zepto::Syntax::Base::STATE_COMMENT_BLOCK, 'javadoc');

    # Constants
    ($tokens) = $hl->tokenize_line('MAX_VALUE = 100;', 0);
    ok(has_token($tokens, 'constant', 0), 'CONSTANT');
};

# =============================================================================
# PHP Grammar Tests
# =============================================================================

subtest 'PHP syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.php');

    # Keywords
    my ($tokens) = $hl->tokenize_line('if ($x === null) return;', 0);
    ok(has_token($tokens, 'keyword', 0), 'if is keyword');
    ok(has_token($tokens, 'keyword', 11), 'null is keyword');
    ok(has_token($tokens, 'keyword', 17), 'return is keyword');

    # Variables
    ($tokens) = $hl->tokenize_line('$foo = $bar;', 0);
    ok(has_token($tokens, 'variable', 0), '$foo is variable');
    ok(has_token($tokens, 'variable', 7), '$bar is variable');

    # Function
    ($tokens) = $hl->tokenize_line('function myFunc() {}', 0);
    ok(has_token($tokens, 'keyword', 0), 'function is keyword');
    ok(has_token($tokens, 'function', 9), 'function name');

    # Class
    ($tokens) = $hl->tokenize_line('class MyClass extends Base {}', 0);
    ok(has_token($tokens, 'keyword', 0), 'class is keyword');
    ok(has_token($tokens, 'type', 6), 'class name');

    # PHP tags
    ($tokens) = $hl->tokenize_line('<?php', 0);
    ok(has_token($tokens, 'tag', 0), 'PHP open tag');

    # Comments
    ($tokens) = $hl->tokenize_line('$x = 1; // comment', 0);
    ok(has_token($tokens, 'comment', 8), 'line comment');

    ($tokens) = $hl->tokenize_line('$x = 1; # shell-style comment', 0);
    ok(has_token($tokens, 'comment', 8), 'shell-style comment');

    # Attributes (PHP 8)
    ($tokens) = $hl->tokenize_line('#[Attribute]', 0);
    ok(has_token($tokens, 'attribute', 0), 'PHP 8 attribute');

    # Operators
    ($tokens) = $hl->tokenize_line('$x ?? $default', 0);
    ok(has_token($tokens, 'operator', 3), 'null coalescing');

    ($tokens) = $hl->tokenize_line('$x?->method()', 0);
    ok(has_token($tokens, 'operator', 2), 'null-safe');
};

# =============================================================================
# Shell Grammar Tests
# =============================================================================

subtest 'Shell syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.sh');

    # Shebang
    my ($tokens) = $hl->tokenize_line('#!/bin/bash', 0);
    ok(has_token($tokens, 'comment', 0), 'shebang');

    # Keywords
    ($tokens) = $hl->tokenize_line('if [ -f "$file" ]; then', 0);
    ok(has_token($tokens, 'keyword', 0), 'if is keyword');
    ok(has_token($tokens, 'keyword', 19), 'then is keyword');

    # Variables
    ($tokens) = $hl->tokenize_line('echo $HOME', 0);
    ok(has_token($tokens, 'variable', 5), '$HOME is variable');

    ($tokens) = $hl->tokenize_line('echo ${PATH}', 0);
    ok(has_token($tokens, 'variable', 7), 'PATH in ${} is variable');

    # Assignment
    ($tokens) = $hl->tokenize_line('FOO=bar', 0);
    ok(has_token($tokens, 'variable', 0), 'FOO is variable in assignment');
    ok(has_token($tokens, 'operator', 3), '= is operator');

    # Function
    ($tokens) = $hl->tokenize_line('function myfunc() {', 0);
    ok(has_token($tokens, 'keyword', 0), 'function is keyword');
    ok(has_token($tokens, 'function', 9), 'function name');

    # Built-in commands
    ($tokens) = $hl->tokenize_line('echo "hello"', 0);
    ok(has_token($tokens, 'function', 0), 'echo is function');

    # Strings
    ($tokens) = $hl->tokenize_line('echo "hello"', 0);
    ok(has_token($tokens, 'string', 5), 'double-quoted string');

    # Comments
    ($tokens) = $hl->tokenize_line('x=1 # comment', 0);
    ok(has_token($tokens, 'comment', 4), 'comment');

    # Operators
    ($tokens) = $hl->tokenize_line('cat file | grep pattern', 0);
    ok(has_token($tokens, 'operator', 9), 'pipe is operator');

    ($tokens) = $hl->tokenize_line('cmd1 && cmd2', 0);
    ok(has_token($tokens, 'operator', 5), '&& is operator');
};

# =============================================================================
# Markdown Grammar Tests
# =============================================================================

subtest 'Markdown syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.md');

    # Headings - each level gets its own token type
    my ($tokens) = $hl->tokenize_line('# Heading 1', 0);
    ok(has_token($tokens, 'punctuation', 0), '# is punctuation');
    ok(has_token($tokens, 'heading1', 2), 'h1 heading text');

    ($tokens) = $hl->tokenize_line('## Heading 2', 0);
    ok(has_token($tokens, 'heading2', 3), 'h2 heading text');

    ($tokens) = $hl->tokenize_line('### Heading 3', 0);
    ok(has_token($tokens, 'heading3', 4), 'h3 heading text');

    ($tokens) = $hl->tokenize_line('#### Heading 4', 0);
    ok(has_token($tokens, 'heading4', 5), 'h4 heading text');

    ($tokens) = $hl->tokenize_line('##### Heading 5', 0);
    ok(has_token($tokens, 'heading5', 6), 'h5 heading text');

    ($tokens) = $hl->tokenize_line('###### Heading 6', 0);
    ok(has_token($tokens, 'heading6', 7), 'h6 heading text');

    # Setext headings
    ($tokens) = $hl->tokenize_line('========', 0);
    ok(has_token($tokens, 'heading1', 0), 'setext === is heading1');

    ($tokens) = $hl->tokenize_line('--------', 0);
    ok(has_token($tokens, 'heading2', 0), 'setext --- is heading2');

    # Lists
    ($tokens) = $hl->tokenize_line('- list item', 0);
    ok(has_token($tokens, 'keyword', 0), '- list marker');

    ($tokens) = $hl->tokenize_line('1. numbered item', 0);
    ok(has_token($tokens, 'keyword', 0), 'numbered list marker');

    # Bold and italic
    ($tokens) = $hl->tokenize_line('**bold text**', 0);
    ok(has_token($tokens, 'bold', 2), 'bold text uses TOKEN_BOLD');

    ($tokens) = $hl->tokenize_line('__bold text__', 0);
    ok(has_token($tokens, 'bold', 2), '__bold__ uses TOKEN_BOLD');

    ($tokens) = $hl->tokenize_line('*italic text*', 0);
    ok(has_token($tokens, 'italic', 1), 'italic text uses TOKEN_ITALIC');

    ($tokens) = $hl->tokenize_line('_italic text_', 0);
    ok(has_token($tokens, 'italic', 1), '_italic_ uses TOKEN_ITALIC');

    # Code
    ($tokens) = $hl->tokenize_line('inline `code` here', 0);
    ok(has_token($tokens, 'function', 7), 'inline code');

    # Fenced code block
    my $state;
    ($tokens, $state) = $hl->tokenize_line('```javascript', 0);
    is($state, 20, 'fenced code block starts');
    ok(has_token($tokens, 'type', 3), 'language name');

    ($tokens, $state) = $hl->tokenize_line('let x = 1;', 1);
    is($state, 20, 'in fenced code block');
    ok(has_token($tokens, 'function', 0), 'code block content');

    ($tokens, $state) = $hl->tokenize_line('```', 2);
    is($state, Zepto::Syntax::Base::STATE_NORMAL, 'fenced code block ends');

    # Links
    ($tokens) = $hl->tokenize_line('[link text](http://url)', 0);
    ok(has_token($tokens, 'string', 1), 'link text');
    ok(has_token($tokens, 'tag', 12), 'link URL');

    # Autolinks
    ($tokens) = $hl->tokenize_line('<http://example.com>', 0);
    ok(has_token($tokens, 'tag', 1), 'autolink URL');
};

# =============================================================================
# AsciiDoc Grammar Tests
# =============================================================================

subtest 'AsciiDoc syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.adoc');

    # Section titles - level-specific tokens
    my ($tokens) = $hl->tokenize_line('= Document Title', 0);
    ok(has_token($tokens, 'punctuation', 0), '= is punctuation');
    ok(has_token($tokens, 'heading1', 2), 'h1 section title');

    ($tokens) = $hl->tokenize_line('== Section Title', 0);
    ok(has_token($tokens, 'punctuation', 0), '== is punctuation');
    ok(has_token($tokens, 'heading2', 3), 'h2 section title');

    ($tokens) = $hl->tokenize_line('=== Subsection', 0);
    ok(has_token($tokens, 'heading3', 4), 'h3 section title');

    # Bold
    ($tokens) = $hl->tokenize_line('this is **bold** text', 0);
    ok(has_token($tokens, 'bold', 8), '**bold** uses TOKEN_BOLD');

    ($tokens) = $hl->tokenize_line('this is *bold* text', 0);
    ok(has_token($tokens, 'bold', 8), '*bold* uses TOKEN_BOLD');

    # Italic
    ($tokens) = $hl->tokenize_line('this is __italic__ text', 0);
    ok(has_token($tokens, 'italic', 8), '__italic__ uses TOKEN_ITALIC');

    ($tokens) = $hl->tokenize_line('this is _italic_ text', 0);
    ok(has_token($tokens, 'italic', 8), '_italic_ uses TOKEN_ITALIC');

    # Inline code
    ($tokens) = $hl->tokenize_line('use `code` here', 0);
    ok(has_token($tokens, 'function', 4), 'inline code');

    # Admonition
    ($tokens) = $hl->tokenize_line('NOTE: something', 0);
    ok(has_token($tokens, 'keyword', 0), 'NOTE is keyword');
};

# =============================================================================
# ReStructuredText Grammar Tests
# =============================================================================

subtest 'ReStructuredText syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.rst');

    # Section title underlines
    my ($tokens) = $hl->tokenize_line('============', 0);
    ok(has_token($tokens, 'heading', 0), 'underline is heading');

    # Strong emphasis (bold)
    ($tokens) = $hl->tokenize_line('this is **bold** text', 0);
    ok(has_token($tokens, 'bold', 8), '**bold** uses TOKEN_BOLD');

    # Emphasis (italic)
    ($tokens) = $hl->tokenize_line('this is *italic* text', 0);
    ok(has_token($tokens, 'italic', 8), '*italic* uses TOKEN_ITALIC');

    # Directive
    ($tokens) = $hl->tokenize_line('.. code-block:: python', 0);
    ok(has_token($tokens, 'keyword', 3), 'directive name is keyword');
    ok(has_token($tokens, 'punctuation', 13), ':: is punctuation');

    # Field list
    ($tokens) = $hl->tokenize_line(':author: John', 0);
    ok(has_token($tokens, 'attribute', 0), ':field: is attribute');

    # Inline literal
    ($tokens) = $hl->tokenize_line('use ``code`` here', 0);
    ok(has_token($tokens, 'function', 4), '``code`` is function');
};

# =============================================================================
# Makefile Grammar Tests
# =============================================================================

subtest 'Makefile syntax' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('Makefile');

    # Targets
    my ($tokens) = $hl->tokenize_line('all: build test', 0);
    ok(has_token($tokens, 'function', 0), 'target name');
    ok(has_token($tokens, 'operator', 3), ': is operator');

    # Variables
    ($tokens) = $hl->tokenize_line('CC = gcc', 0);
    ok(has_token($tokens, 'variable', 0), 'CC is variable');
    ok(has_token($tokens, 'operator', 3), '= is operator');

    ($tokens) = $hl->tokenize_line('$(CC) $(CFLAGS)', 0);
    ok(has_token($tokens, 'variable', 2), 'CC in $() is variable');

    # Automatic variables
    ($tokens) = $hl->tokenize_line("\t\$(CC) -o \$@ \$<", 0);
    ok(has_token($tokens, 'variable', 10), '$@ is variable');
    ok(has_token($tokens, 'variable', 13), '$< is variable');

    # Comments
    ($tokens) = $hl->tokenize_line('# this is a comment', 0);
    ok(has_token($tokens, 'comment', 0), 'comment');

    # Conditionals
    ($tokens) = $hl->tokenize_line('ifeq ($(OS),Windows)', 0);
    ok(has_token($tokens, 'keyword', 0), 'ifeq is keyword');

    # Special targets
    ($tokens) = $hl->tokenize_line('.PHONY: all clean', 0);
    ok(has_token($tokens, 'attribute', 0), '.PHONY is attribute');

    # Include
    ($tokens) = $hl->tokenize_line('include config.mk', 0);
    ok(has_token($tokens, 'keyword', 0), 'include is keyword');
};

# =============================================================================
# Edge Cases and Robustness
# =============================================================================

subtest 'Edge cases' => sub {
    my $hl = Zepto::Highlighter->new();

    # Empty lines
    $hl->set_file('test.pl');
    my ($tokens) = $hl->tokenize_line('', 0);
    is(scalar @$tokens, 0, 'empty line produces no tokens');

    # Very long lines
    my $long_line = 'my $x = ' . ('a' x 1000) . ';';
    ($tokens) = $hl->tokenize_line($long_line, 0);
    ok(defined $tokens, 'long line handled');

    # Unicode content
    $hl->set_file('test.py');
    ($tokens) = $hl->tokenize_line('s = "héllo wörld"', 0);
    ok(has_token($tokens, 'string', 4), 'unicode string');

    # Nested quotes (tricky)
    $hl->set_file('test.js');
    ($tokens) = $hl->tokenize_line('s = "he said \\"hello\\""', 0);
    ok(has_token($tokens, 'string', 4), 'escaped quotes in string');

    # Invalid syntax (should not crash)
    $hl->set_file('test.pl');
    ($tokens) = $hl->tokenize_line('if if if {{{', 0);
    ok(defined $tokens, 'invalid syntax handled gracefully');

    # No grammar
    $hl->set_file('test.xyz');
    ($tokens) = $hl->tokenize_line('some content', 0);
    is(scalar @$tokens, 0, 'unknown language produces no tokens');
};

# =============================================================================
# Performance/Stress Test
# =============================================================================

subtest 'Performance' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    # Tokenize many lines
    my $start = time();
    for my $i (0 .. 999) {
        my $line = "const x$i = function() { return $i * 2; }; // comment $i";
        $hl->tokenize_line($line, $i);
    }
    my $elapsed = time() - $start;

    ok($elapsed < 5, "1000 lines tokenized in < 5 seconds (took ${elapsed}s)");
};

done_testing();
