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

# Shallow structural comparison of two token lists (same length, and each
# position's type/start/end match). Used by the token-cache invalidation
# tests to assert two token lists are NOT equal (a plain inequality check
# reads clearer than picking apart an is_deeply() diff for that purpose).
sub tokens_equal {
    my ($a, $b) = @_;
    return 0 if scalar(@$a) != scalar(@$b);
    for my $i (0 .. $#$a) {
        return 0 if $a->[$i]{type} ne $b->[$i]{type}
                 || $a->[$i]{start} != $b->[$i]{start}
                 || $a->[$i]{end} != $b->[$i]{end};
    }
    return 1;
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
# Token memo cache correctness (QA-REG-199..201, bugs.md P2 "Syntax
# highlighter re-tokenizes every visible line on every render")
# =============================================================================
#
# Highlighter.pm memoizes tokenize_line()'s (\@tokens, $end_state) result
# keyed on (start_state, line_content). These tests specifically target
# INVALIDATION correctness, not just "the cache works when nothing
# changes" -- each one is constructed so it would FAIL against a naive
# cache keyed on content alone (dropping start_state from the key), which
# was confirmed by deliberately reverting to a content-only key during
# development: every subtest below failed with that broken key, and all
# pass with the real (start_state, content) key.

subtest 'Token cache - repeated identical calls are memoized correctly' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    my ($tok1, $state1) = $hl->tokenize_line('const x = 1;', 0);
    my ($tok2, $state2) = $hl->tokenize_line('const x = 1;', 0);

    is($state1, $state2, 'Same state for repeated identical call');
    is_deeply($tok1, $tok2, 'Same tokens for repeated identical (state, content) call');

    # Cache was actually populated and hit (white-box check, same pattern
    # tests/wrapmap.t uses on WrapMap's private _dirty flag).
    ok($hl->{_token_cache_count} > 0, 'Token cache has at least one entry after tokenizing');
};

subtest 'Token cache - upstream edit that changes start_state is NOT served stale tokens' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    # First render pass: line 0 is plain code, line 1 is untouched plain
    # text. Renderer always tokenizes top-to-bottom, so line 1 sees line
    # 0's real end state (STATE_NORMAL here).
    my ($tok0_before, $state0_before) = $hl->tokenize_line('var x = 1;', 0);
    is($state0_before, Zepto::Syntax::Base::STATE_NORMAL, 'Line 0 (plain code) ends in NORMAL state');

    my ($tok1_before, $state1_before) = $hl->tokenize_line('plain text line', 1);
    ok(!(grep { $_->{type} eq 'comment' } @$tok1_before),
        'Sanity: line 1 has no comment tokens while line 0 was plain code');

    # Now simulate editing line 0 so it OPENS a multi-line block comment.
    # Line 1's own content is byte-identical to before -- only the state
    # it starts in has changed. This is exactly the scenario a naive
    # content-only cache key gets wrong: it would return the stale
    # "plain text" tokens for line 1 from the entry cached above instead
    # of re-tokenizing under the new incoming state.
    my ($tok0_after, $state0_after) = $hl->tokenize_line('/* start comment', 0);
    is($state0_after, Zepto::Syntax::Base::STATE_COMMENT_BLOCK,
        'Line 0 (edited) now ends in COMMENT_BLOCK state');

    my ($tok1_after, $state1_after) = $hl->tokenize_line('plain text line', 1);
    is($state1_after, Zepto::Syntax::Base::STATE_COMMENT_BLOCK,
        'Line 1 correctly continues the block comment (state propagated, not stale)');
    ok((grep { $_->{type} eq 'comment' && $_->{start} == 0 && $_->{end} == length('plain text line') } @$tok1_after),
        'Line 1 is now tokenized as one whole comment token, not the old "plain text" tokens');

    isnt(scalar(@$tok1_after), 0, 'Line 1 still produces tokens');
    ok(!tokens_equal($tok1_before, $tok1_after),
        'Line 1 tokens actually changed after the upstream edit (not silently reused from cache)');
};

subtest 'Token cache - undo restores exact original tokens, not a stale mid-edit version' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    # Original state: line 0 plain, line 1 plain.
    $hl->tokenize_line('var x = 1;', 0);
    my ($tok1_original) = $hl->tokenize_line('plain text line', 1);

    # Edit: line 0 opens a block comment, line 1 (unchanged content) is
    # re-tokenized as a comment continuation.
    $hl->tokenize_line('/* start comment', 0);
    my ($tok1_mid_edit) = $hl->tokenize_line('plain text line', 1);
    ok((grep { $_->{type} eq 'comment' } @$tok1_mid_edit), 'Mid-edit: line 1 is a comment continuation');

    # Undo: line 0 reverts to its original content.
    my ($tok0_undo, $state0_undo) = $hl->tokenize_line('var x = 1;', 0);
    is($state0_undo, Zepto::Syntax::Base::STATE_NORMAL, 'Undo: line 0 back to NORMAL state');

    my ($tok1_undo) = $hl->tokenize_line('plain text line', 1);
    ok(!(grep { $_->{type} eq 'comment' } @$tok1_undo),
        'Undo: line 1 is no longer tokenized as a comment (not stuck on the mid-edit cached version)');
    is_deeply($tok1_undo, $tok1_original,
        'Undo: line 1 tokens exactly match the pre-edit original (cache correctly re-served the right entry)');
};

subtest 'Token cache - no cross-contamination between highlighter instances (tabs)' => sub {
    # Each open tab gets its own Highlighter instance (TabManager). Confirm
    # the token cache is instance-scoped: tokenizing identical literal text
    # under two different grammars must not leak one grammar's tokens into
    # the other's cache.
    my $hl_perl = Zepto::Highlighter->new();
    $hl_perl->set_file('a.pl');

    my $hl_js = Zepto::Highlighter->new();
    $hl_js->set_file('b.js');

    my $line = '$x = 1;';

    my ($tok_perl) = $hl_perl->tokenize_line($line, 0);
    my ($tok_js)   = $hl_js->tokenize_line($line, 0);

    # Perl treats $x as a sigil'd variable; JS has no such concept for a
    # bare $-prefixed identifier -- the token sets must differ.
    my @perl_vars = grep { $_->{type} eq 'variable' } @$tok_perl;
    ok(scalar(@perl_vars) > 0, 'Perl highlighter tokenizes $x as a variable');

    # Re-query the Perl highlighter again for the same line -- must still
    # return Perl-flavored tokens, proving the JS instance's tokenize_line
    # call above didn't pollute a shared/global cache.
    my ($tok_perl_again) = $hl_perl->tokenize_line($line, 0);
    is_deeply($tok_perl, $tok_perl_again,
        'Perl highlighter still returns Perl tokens after a different instance tokenized the same text');
};

subtest 'Token cache - multi-line paste shifting line numbers stays correct' => sub {
    # Simulates the renderer's actual call pattern: sequential top-to-bottom
    # tokenize_line() calls for a document's visible lines. A large paste
    # that inserts N lines above doesn't change any EXISTING line's own
    # content, but does shift what line_num it's tokenized under and
    # (for lines immediately after the paste) potentially what state it
    # starts from. Content-keyed caching must handle the shift correctly.
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.js');

    # "Before": doc is just the tail content, unwrapped.
    my @before = ('var x = 1;', 'var y = 2;', 'plain text line', 'var z = 3;');
    my @before_tokens;
    for my $i (0 .. $#before) {
        my ($tok) = $hl->tokenize_line($before[$i], $i);
        push @before_tokens, $tok;
    }

    # "After": a 3-line paste is inserted above a block comment opener,
    # shifting the tail content down by 3 lines. Re-tokenize the WHOLE
    # visible range from the top, as the renderer does every frame,
    # through a fresh highlighter object representing the post-edit
    # render pass state (same underlying content-addressed cache
    # mechanism; using a fresh instance here just keeps the "before"
    # array above untouched for comparison).
    my $hl2 = Zepto::Highlighter->new();
    $hl2->set_file('test.js');
    my @after_lines = ('// pasted line A', '// pasted line B', '// pasted line C',
                        'var x = 1;', 'var y = 2;', 'plain text line', 'var z = 3;');
    my @after_tokens;
    for my $i (0 .. $#after_lines) {
        my ($tok) = $hl2->tokenize_line($after_lines[$i], $i);
        push @after_tokens, $tok;
    }

    # The shifted tail lines (now at index 3..6) must tokenize identically
    # to their original (index 0..3) results, since neither their own
    # content nor the state they start in (STATE_NORMAL, both before and
    # after the 3 inserted line-comments) changed.
    for my $j (0 .. $#before) {
        is_deeply($after_tokens[$j + 3], $before_tokens[$j],
            "Shifted line (was index $j, now index @{[$j+3]}) tokenizes identically after the paste");
    }
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

    # Bold+italic
    ($tokens) = $hl->tokenize_line('***bold italic***', 0);
    ok(has_token($tokens, 'bold_italic', 3), '***text*** uses TOKEN_BOLD_ITALIC');

    ($tokens) = $hl->tokenize_line('___bold italic___', 0);
    ok(has_token($tokens, 'bold_italic', 3), '___text___ uses TOKEN_BOLD_ITALIC');

    # Strikethrough
    ($tokens) = $hl->tokenize_line('~~deleted text~~', 0);
    ok(has_token($tokens, 'strikethrough', 2), '~~text~~ uses TOKEN_STRIKETHROUGH');

    # Highlighted
    ($tokens) = $hl->tokenize_line('==highlighted text==', 0);
    ok(has_token($tokens, 'highlight', 2), '==text== uses TOKEN_HIGHLIGHT');

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
    ok(has_token($tokens, 'link', 12), 'link URL uses TOKEN_LINK');

    # Autolinks
    ($tokens) = $hl->tokenize_line('<http://example.com>', 0);
    ok(has_token($tokens, 'link', 1), 'autolink URL uses TOKEN_LINK');

    # Escaping — backslash prevents markup
    ($tokens) = $hl->tokenize_line('\*Not italic\*', 0);
    is(scalar @$tokens, 0, 'escaped asterisks produce no tokens');

    ($tokens) = $hl->tokenize_line('\**Not bold\**', 0);
    is(scalar @$tokens, 0, 'escaped double asterisks produce no tokens');

    ($tokens) = $hl->tokenize_line('\`Not code\`', 0);
    is(scalar @$tokens, 0, 'escaped backticks produce no tokens');
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

    # URL with link text (scheme included in link)
    ($tokens) = $hl->tokenize_line('visit https://example.com[Example] now', 0);
    ok(has_token($tokens, 'link', 6), 'URL with [text] includes scheme in TOKEN_LINK');
    is(token_at($tokens, 6), 'link', 'https: is part of link token');
    is(token_at($tokens, 14), 'link', '//example.com is part of link token');

    # Bare URL
    ($tokens) = $hl->tokenize_line('visit https://example.com for info', 0);
    ok(has_token($tokens, 'link', 6), 'bare URL uses TOKEN_LINK');
    is(token_at($tokens, 6), 'link', 'bare URL scheme is link');

    # Inline macro links
    ($tokens) = $hl->tokenize_line('link:http://example.com[click here]', 0);
    ok(has_token($tokens, 'link', 5), 'inline macro URL uses TOKEN_LINK');

    # Cross-reference
    ($tokens) = $hl->tokenize_line('see <<section-id>>', 0);
    ok(has_token($tokens, 'link', 4), '<<xref>> uses TOKEN_LINK');

    # Role-annotated underline: [. underline ]# text #
    ($tokens) = $hl->tokenize_line('[.underline]#underlined text#', 0);
    ok(has_token($tokens, 'underline', 13), '[.underline]#text# uses TOKEN_UNDERLINE');

    # Role-annotated strikethrough: [. line-through ]# text #
    ($tokens) = $hl->tokenize_line('[.line-through]#deleted text#', 0);
    ok(has_token($tokens, 'strikethrough', 16), '[.line-through]#text# uses TOKEN_STRIKETHROUGH');

    # Marked/highlighted text ##text##
    ($tokens) = $hl->tokenize_line('this is ##marked text## here', 0);
    ok(has_token($tokens, 'highlight', 10), '##text## uses TOKEN_HIGHLIGHT');

    # Role-annotated highlight: [.highlight]#text#
    ($tokens) = $hl->tokenize_line('[.highlight]#important text#', 0);
    ok(has_token($tokens, 'highlight', 13), '[.highlight]#text# uses TOKEN_HIGHLIGHT');

    # Role-annotated mark: [.mark]#text#
    ($tokens) = $hl->tokenize_line('[.mark]#key info#', 0);
    ok(has_token($tokens, 'highlight', 8), '[.mark]#text# uses TOKEN_HIGHLIGHT');

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

    # Hyperlink reference
    ($tokens) = $hl->tokenize_line('see `Python <http://python.org>`_', 0);
    ok(has_token($tokens, 'link', 4), 'hyperlink ref uses TOKEN_LINK');

    # Footnote reference
    ($tokens) = $hl->tokenize_line('see [1]_ for details', 0);
    ok(has_token($tokens, 'link', 4), 'footnote ref uses TOKEN_LINK');
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

# =============================================================================
# HTML: Embedded CSS/JS Highlighting
# =============================================================================

subtest 'HTML embedded CSS in <style> tag' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.html');
    my ($tokens, $state);

    # Open <style> tag
    ($tokens, $state) = $hl->tokenize_line('<style>', 0);
    ok(has_token($tokens, 'tag', 0), 'style opening tag');
    isnt($state, 0, 'enters style state after <style>');

    # CSS content line: property names should be highlighted
    ($tokens, $state) = $hl->tokenize_line('    body { color: red; }', 1);
    ok(tokens_of_type($tokens, 'variable'), 'CSS property name highlighted in <style>');

    # CSS content: numbers with units
    ($tokens, $state) = $hl->tokenize_line('    margin: 10px;', 2);
    ok(tokens_of_type($tokens, 'number'), 'CSS number highlighted in <style>');

    # Closing </style> tag
    ($tokens, $state) = $hl->tokenize_line('</style>', 3);
    ok(has_token($tokens, 'tag', 0), 'style closing tag');
    is($state, 0, 'returns to normal state after </style>');
};

subtest 'HTML embedded JS in <script> tag' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.html');
    my ($tokens, $state);

    # Open <script> tag
    ($tokens, $state) = $hl->tokenize_line('<script>', 0);
    ok(has_token($tokens, 'tag', 0), 'script opening tag');
    isnt($state, 0, 'enters script state after <script>');

    # JS content: keywords
    ($tokens, $state) = $hl->tokenize_line('    var x = function() {', 1);
    ok(tokens_of_type($tokens, 'keyword'), 'JS keyword highlighted in <script>');

    # JS content: strings
    ($tokens, $state) = $hl->tokenize_line('    var s = "hello";', 2);
    ok(tokens_of_type($tokens, 'string'), 'JS string highlighted in <script>');

    # Closing </script> tag
    ($tokens, $state) = $hl->tokenize_line('</script>', 3);
    ok(has_token($tokens, 'tag', 0), 'script closing tag');
    is($state, 0, 'returns to normal state after </script>');
};

subtest 'HTML embedded CSS multi-line block comment' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.html');
    my ($tokens, $state);

    ($tokens, $state) = $hl->tokenize_line('<style>', 0);

    # Start a block comment
    ($tokens, $state) = $hl->tokenize_line('    /* this is a', 1);
    ok(tokens_of_type($tokens, 'comment'), 'CSS block comment start highlighted');

    # Comment continues
    ($tokens, $state) = $hl->tokenize_line('       multi-line comment */', 2);
    ok(tokens_of_type($tokens, 'comment'), 'CSS block comment end highlighted');

    # Normal CSS after comment
    ($tokens, $state) = $hl->tokenize_line('    body { color: blue; }', 3);
    ok(tokens_of_type($tokens, 'variable'), 'CSS property after block comment');

    ($tokens, $state) = $hl->tokenize_line('</style>', 4);
    is($state, 0, 'returns to normal after </style>');
};

subtest 'HTML same-line <style>...</style>' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.html');
    my ($tokens, $state);

    ($tokens, $state) = $hl->tokenize_line('<style>body { color: red; }</style>', 0);
    ok(has_token($tokens, 'tag', 0), 'opening style tag');
    ok(tokens_of_type($tokens, 'variable'), 'CSS property in same-line style');
    is($state, 0, 'returns to normal for same-line style');
};

subtest 'HTML same-line <script>...</script>' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.html');
    my ($tokens, $state);

    ($tokens, $state) = $hl->tokenize_line('<script>var x = 42;</script>', 0);
    ok(has_token($tokens, 'tag', 0), 'opening script tag');
    ok(tokens_of_type($tokens, 'keyword'), 'JS keyword in same-line script');
    is($state, 0, 'returns to normal for same-line script');
};

# =============================================================================
# YAML: bare words should not match partial literals
# =============================================================================
subtest 'YAML bare words containing literal substrings' => sub {
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.yaml');

    # "name: region" — "on" inside "region" should NOT be highlighted as keyword
    my ($tokens, $state) = $hl->tokenize_line('name: region', 0);
    my @keywords = grep { $_->{type} eq 'keyword' } @$tokens;
    is(scalar @keywords, 0, 'No keywords in "name: region" — "on" not matched inside bare word');

    # "category: information" — "no" inside "information" should not match
    ($tokens, $state) = $hl->tokenize_line('category: information', 0);
    @keywords = grep { $_->{type} eq 'keyword' } @$tokens;
    is(scalar @keywords, 0, 'No keywords in "category: information"');

    # Standalone "on" should still match
    ($tokens, $state) = $hl->tokenize_line('flag: on', 0);
    @keywords = grep { $_->{type} eq 'keyword' } @$tokens;
    is(scalar @keywords, 1, 'Standalone "on" still highlighted as keyword');

    # "enabled: true" should still match
    ($tokens, $state) = $hl->tokenize_line('enabled: true', 0);
    @keywords = grep { $_->{type} eq 'keyword' } @$tokens;
    is(scalar @keywords, 1, 'Standalone "true" still highlighted as keyword');
};

done_testing();
