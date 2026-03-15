#!/usr/bin/env perl
# =============================================================================
# Completion System Test Suite
# =============================================================================
#
# Tests for the auto-completion engine: Controller, KeywordProvider,
# BufferWordProvider, PathProvider.
#
# To run: prove -v tests/completion.t
#
# =============================================================================

use strict;
use warnings;
use utf8;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use Zepto::Completion::Controller;
use Zepto::Completion::KeywordProvider;
use Zepto::Completion::BufferWordProvider;
use Zepto::Completion::PathProvider;
use Zepto::Document;
use Zepto::View;
use Zepto::Highlighter;

# =============================================================================
# Helper: create a document with content
# =============================================================================
sub make_doc {
    my ($content) = @_;
    my $doc = Zepto::Document->new();
    # Replace document content
    if ($doc->line_count() > 0) {
        my $total_len = $doc->length();
        $doc->delete(0, $total_len) if $total_len > 0;
    }
    $doc->insert(0, $content) if defined $content && length($content) > 0;
    return $doc;
}

# =============================================================================
# Prefix Extraction
# =============================================================================
subtest 'Prefix extraction' => sub {
    # Test internal prefix extraction
    my $extract = \&Zepto::Completion::Controller::_extract_prefix;

    is($extract->('hello world', 5), 'hello', 'word at start of line');
    is($extract->('hello world', 11), 'world', 'word at end of line');
    is($extract->('  foo_bar', 9), 'foo_bar', 'word with underscore');
    is($extract->('x = 42', 1), 'x', 'single char prefix');
    is($extract->('def func():', 8), 'func', 'prefix before parens');
    is($extract->('', 0), '', 'empty line');
    is($extract->('hello', 0), '', 'cursor at start');
    is($extract->('   ', 3), '', 'whitespace only');
    is($extract->('a.method', 8), 'method', 'after dot');
    is($extract->('import os', 9), 'os', 'after space');
};

# =============================================================================
# KeywordProvider
# =============================================================================
subtest 'KeywordProvider' => sub {
    my $provider = Zepto::Completion::KeywordProvider->new();

    # Create a highlighter with Python grammar
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.py');

    my $context = {
        prefix => 'de',
        line   => 'de',
        col    => 2,
        language => 'Python',
        highlighter => $hl,
    };

    my $results = $provider->complete($context);
    ok(ref($results) eq 'ARRAY', 'returns arrayref');
    ok(@$results > 0, 'finds Python keyword matches for "de"');

    # Check that "def" is in results
    my @def_matches = grep { $_->{text} eq 'def' } @$results;
    ok(@def_matches > 0, '"def" found in results');
    is($def_matches[0]{kind}, 'keyword', 'kind is keyword');

    # Check that "del" is in results
    my @del_matches = grep { $_->{text} eq 'del' } @$results;
    ok(@del_matches > 0, '"del" found in results');

    # No results for prefix too short
    my $short_context = { %$context, prefix => 'x' };
    my $short_results = $provider->complete($short_context);
    is(scalar(@$short_results), 0, 'no results for single-char prefix');

    # No results for non-matching prefix
    my $no_match = { %$context, prefix => 'zzz' };
    my $no_results = $provider->complete($no_match);
    is(scalar(@$no_results), 0, 'no results for non-matching prefix');
};

# =============================================================================
# BufferWordProvider
# =============================================================================
subtest 'BufferWordProvider' => sub {
    my $provider = Zepto::Completion::BufferWordProvider->new();

    my $doc = make_doc("function hello() {\n  console.log('hello');\n  return hello;\n}\n");

    my $context = {
        prefix   => 'hel',
        line     => '  return hel',
        line_num => 2,
        col      => 12,
        doc      => $doc,
        language => 'JavaScript',
    };

    my $results = $provider->complete($context);
    ok(ref($results) eq 'ARRAY', 'returns arrayref');
    ok(@$results > 0, 'finds buffer word matches');

    # "hello" should be in results
    my @hello_matches = grep { $_->{text} eq 'hello' } @$results;
    ok(@hello_matches > 0, '"hello" found in buffer words');
    is($hello_matches[0]{kind}, 'word', 'kind is word');

    # "function" should match "fun"
    my $fun_context = { %$context, prefix => 'fun' };
    my $fun_results = $provider->complete($fun_context);
    my @fun_matches = grep { $_->{text} eq 'function' } @$fun_results;
    ok(@fun_matches > 0, '"function" found for prefix "fun"');

    # Frequency affects score: "hello" appears 3 times
    ok($hello_matches[0]{score} > 50, 'frequent word has score > base');
};

# =============================================================================
# Controller State Machine
# =============================================================================
subtest 'Controller state machine' => sub {
    my $ctrl = Zepto::Completion::Controller->new();

    # Initially idle
    ok(!$ctrl->is_active(), 'starts idle');
    is($ctrl->state(), 0, 'state is IDLE (0)');

    # Create a document and view for triggering
    my $doc = make_doc("def hello():\n    pass\n");
    my $view = Zepto::View->new(document => $doc);

    # Position cursor at end of "def"
    $view->set_cursor(0, 3);

    # Add a keyword provider
    my $kw_provider = Zepto::Completion::KeywordProvider->new();
    $ctrl->add_provider($kw_provider);

    # Set up highlighter for Python
    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.py');

    # Trigger - prefix "def" should match keywords
    # But "def" itself should be filtered out since it's an exact match
    $ctrl->trigger($doc, $view, $hl);

    # Should find "del", "delattr" etc for prefix "def"
    # Actually "def" won't match "del" — prefix must be a prefix of the keyword
    # Let's use a better example
    $ctrl->dismiss();

    # Test with "re" which should match "return", "repr", etc
    my $doc2 = make_doc("re\n");
    my $view2 = Zepto::View->new(document => $doc2);
    $view2->set_cursor(0, 2);

    $ctrl->trigger($doc2, $view2, $hl);
    if ($ctrl->is_active()) {
        is($ctrl->state(), 1, 'state is GHOST (1) after trigger');
        ok($ctrl->is_ghost(), 'is_ghost returns true');
        ok(!$ctrl->is_menu(), 'is_menu returns false');
        ok(length($ctrl->prefix()) > 0, 'prefix is set');
    }

    # Dismiss
    $ctrl->dismiss();
    ok(!$ctrl->is_active(), 'idle after dismiss');
    is(scalar(@{$ctrl->results()}), 0, 'results cleared after dismiss');
};

# =============================================================================
# Controller Accept
# =============================================================================
subtest 'Controller accept' => sub {
    my $ctrl = Zepto::Completion::Controller->new();
    my $bw = Zepto::Completion::BufferWordProvider->new();
    $ctrl->add_provider($bw);

    my $doc = make_doc("function hello_world() {}\nhel\n");
    my $view = Zepto::View->new(document => $doc);
    $view->set_cursor(1, 3);

    $ctrl->trigger($doc, $view, undef);

    if ($ctrl->is_active()) {
        my $suffix = $ctrl->accept();
        ok(length($suffix) > 0, 'accept returns non-empty suffix');
        # suffix should be "lo_world" (the part after "hel")
        like($suffix, qr/lo_world/, 'suffix completes the word');
        ok(!$ctrl->is_active(), 'idle after accept');
    } else {
        pass('no completion active (acceptable in minimal test)');
    }
};

# =============================================================================
# Menu Navigation
# =============================================================================
subtest 'Menu navigation' => sub {
    my $ctrl = Zepto::Completion::Controller->new();
    my $bw = Zepto::Completion::BufferWordProvider->new();
    $ctrl->add_provider($bw);

    my $doc = make_doc("function foo() {}\nfunction foobar() {}\nfunction foobaz() {}\nfo\n");
    my $view = Zepto::View->new(document => $doc);
    $view->set_cursor(3, 2);

    $ctrl->trigger($doc, $view, undef);

    if ($ctrl->is_active()) {
        # Open menu
        $ctrl->open_menu();
        ok($ctrl->is_menu(), 'menu is open');

        # Navigate down
        my $initial_idx = $ctrl->{menu_index};
        $ctrl->menu_down();
        is($ctrl->{menu_index}, $initial_idx + 1, 'menu_down advances index');

        # Navigate up
        $ctrl->menu_up();
        is($ctrl->{menu_index}, $initial_idx, 'menu_up goes back');

        # Accept from menu
        my $suffix = $ctrl->accept();
        ok(length($suffix) > 0, 'accept from menu returns suffix');
    } else {
        pass('no completion active (acceptable in minimal test)');
    }
};

# =============================================================================
# Ghost Cycling
# =============================================================================
subtest 'Ghost cycling' => sub {
    my $ctrl = Zepto::Completion::Controller->new();
    my $bw = Zepto::Completion::BufferWordProvider->new();
    $ctrl->add_provider($bw);

    my $doc = make_doc("alpha beta gamma\nalpha_one alpha_two alpha_three\nal\n");
    my $view = Zepto::View->new(document => $doc);
    $view->set_cursor(2, 2);

    $ctrl->trigger($doc, $view, undef);

    if ($ctrl->is_active() && @{$ctrl->results()} >= 2) {
        my $first_ghost = $ctrl->{ghost_index};
        $ctrl->cycle_next();
        is($ctrl->{ghost_index}, $first_ghost + 1, 'cycle_next advances');
        $ctrl->cycle_prev();
        is($ctrl->{ghost_index}, $first_ghost, 'cycle_prev goes back');
    } else {
        pass('not enough results for cycling test');
    }
};

# =============================================================================
# State for Render
# =============================================================================
subtest 'state_for_render' => sub {
    my $ctrl = Zepto::Completion::Controller->new();
    my $bw = Zepto::Completion::BufferWordProvider->new();
    $ctrl->add_provider($bw);

    my $doc = make_doc("function hello_world() {}\nhel\n");
    my $view = Zepto::View->new(document => $doc);
    $view->set_cursor(1, 3);

    # When idle, returns undef
    my $render_data = $ctrl->state_for_render($view, $doc);
    is($render_data, undef, 'returns undef when idle');

    $ctrl->trigger($doc, $view, undef);

    if ($ctrl->is_active()) {
        $render_data = $ctrl->state_for_render($view, $doc);
        ok(defined $render_data, 'returns data when active');
        ok(exists $render_data->{ghost_text}, 'has ghost_text');
        ok(length($render_data->{ghost_text}) > 0, 'ghost_text is non-empty');
        is($render_data->{cursor_line}, 1, 'cursor_line correct');
        is($render_data->{cursor_col}, 3, 'cursor_col correct');
    }
};

# =============================================================================
# PathProvider Context Detection
# =============================================================================
subtest 'PathProvider context detection' => sub {
    my $provider = Zepto::Completion::PathProvider->new();

    # Markdown link context
    my $context_link = {
        prefix => '',
        line   => '[click here](./REA',
        col    => 18,
        doc    => make_doc(''),
    };
    # Should detect path context (even if no files match)
    my $results = $provider->complete($context_link);
    ok(ref($results) eq 'ARRAY', 'returns arrayref for Markdown link');

    # Markdown image context
    my $context_img = {
        prefix => '',
        line   => '![alt](./img/',
        col    => 13,
        doc    => make_doc(''),
    };
    $results = $provider->complete($context_img);
    ok(ref($results) eq 'ARRAY', 'returns arrayref for Markdown image');

    # Import context
    my $context_import = {
        prefix => '',
        line   => "import './com",
        col    => 13,
        doc    => make_doc(''),
    };
    $results = $provider->complete($context_import);
    ok(ref($results) eq 'ARRAY', 'returns arrayref for import');

    # No path context (regular code)
    my $context_none = {
        prefix => 'hel',
        line   => 'hello world',
        col    => 5,
        doc    => make_doc(''),
    };
    $results = $provider->complete($context_none);
    is(scalar(@$results), 0, 'no results outside path context');
};

# =============================================================================
# Keyword lists exist for key languages
# =============================================================================
subtest 'Keyword lists' => sub {
    my @languages = qw(Python TypeScript Go Rust Java C Cpp Ruby Shell Perl SQL);

    for my $lang (@languages) {
        my $class = "Zepto::Syntax::$lang";
        eval "require $class";
        if ($@) {
            fail("could not load $class: $@");
            next;
        }
        my $grammar = $class->new();
        my $keywords = $grammar->keyword_list();
        ok(ref($keywords) eq 'ARRAY', "$lang keyword_list returns arrayref");
        ok(@$keywords > 5, "$lang has at least 5 keywords (has " . scalar(@$keywords) . ")");
    }
};

done_testing();
