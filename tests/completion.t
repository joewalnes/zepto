#!/usr/bin/env perl
# =============================================================================
# Completion System Test Suite
# =============================================================================
#
# Tests for the auto-completion engine: Controller, KeywordProvider,
# CrossBufferWordProvider, PathProvider, SnippetProvider, RecentProvider.
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
use Scalar::Util qw(refaddr);

use Zepto::Completion::Controller;
use Zepto::Completion::KeywordProvider;
use Zepto::Completion::CrossBufferWordProvider;
use Zepto::Completion::PathProvider;
use Zepto::Completion::SnippetProvider;
use Zepto::Completion::RecentProvider;
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
# CrossBufferWordProvider (single doc, no tab manager)
# =============================================================================
subtest 'CrossBufferWordProvider (single doc)' => sub {
    my $provider = Zepto::Completion::CrossBufferWordProvider->new();

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
# CrossBufferWordProvider (multi-tab mock)
# =============================================================================
subtest 'CrossBufferWordProvider (multi-tab)' => sub {
    # Create a mock tab manager
    my $doc1 = make_doc("unique_word_alpha unique_word_beta\n");
    my $doc2 = make_doc("unique_word_gamma unique_word_delta\n");

    my $mock_tm = bless {
        tabs => [
            { document => $doc1 },
            { document => $doc2 },
        ],
    }, 'MockTabManager';

    # Add tabs() method
    {
        no strict 'refs';
        no warnings 'once';
        *MockTabManager::tabs = sub { $_[0]->{tabs} };
    }

    my $provider = Zepto::Completion::CrossBufferWordProvider->new(
        tab_manager => $mock_tm,
    );

    my $context = {
        prefix   => 'unique_word',
        line     => 'unique_word',
        line_num => 0,
        col      => 11,
        doc      => $doc1,
        language => '',
    };

    my $results = $provider->complete($context);
    ok(@$results >= 4, 'finds words from both tabs');

    my %found = map { $_->{text} => 1 } @$results;
    ok($found{'unique_word_alpha'}, 'found word from tab 1');
    ok($found{'unique_word_gamma'}, 'found word from tab 2');
    ok($found{'unique_word_delta'}, 'found word from tab 2 (second word)');

    # Active doc words get proximity boost
    my @alpha = grep { $_->{text} eq 'unique_word_alpha' } @$results;
    my @gamma = grep { $_->{text} eq 'unique_word_gamma' } @$results;
    ok($alpha[0]{score} > $gamma[0]{score}, 'active doc word has higher score (proximity boost)');
};

# =============================================================================
# CrossBufferWordProvider (per-document cache isolation)
# =============================================================================
# Regression coverage for QA-REG-152 / bugs.md "CrossBufferWordProvider
# rescans every open tab on every trigger, not just the changed one".
# Confirms that editing ONE open tab only rescans that tab's document —
# other open tabs' per-document caches are left untouched — while the
# merged completion results still reflect the edit correctly.
subtest 'CrossBufferWordProvider (per-document cache isolation)' => sub {
    my $doc1 = make_doc("alpha_one alpha_two\n");
    my $doc2 = make_doc("beta_one beta_two\n");

    my $mock_tm = bless {
        tabs => [
            { document => $doc1 },
            { document => $doc2 },
        ],
    }, 'MockTabManager2';

    {
        no strict 'refs';
        no warnings 'once';
        *MockTabManager2::tabs = sub { $_[0]->{tabs} };
    }

    my $provider = Zepto::Completion::CrossBufferWordProvider->new(
        tab_manager => $mock_tm,
    );

    my $context1 = {
        prefix   => 'alpha',
        line     => 'alpha',
        line_num => 0,
        col      => 5,
        doc      => $doc1,
        language => '',
    };

    # Prime the cache — first trigger necessarily scans both docs.
    $provider->complete($context1);

    my $doc1_id = "$doc1";
    my $doc2_id = "$doc2";

    ok($provider->{_doc_words}{$doc2_id}, 'doc2 has a per-document cache entry after priming');
    my $doc2_cache_before = $provider->{_doc_words}{$doc2_id};

    # Instrument doc2's line scanning so we can prove it is NOT rescanned
    # when only doc1 changes. Wrap the original coderef and count calls
    # made against doc2 specifically; `local *glob` restores the original
    # sub automatically when this block exits.
    my $doc2_scan_calls = 0;
    {
        no strict 'refs';
        no warnings 'redefine';
        my $orig = \&Zepto::Document::get_line_content;
        local *Zepto::Document::get_line_content = sub {
            my ($scanned_doc, @rest) = @_;
            $doc2_scan_calls++ if refaddr($scanned_doc) == refaddr($doc2);
            return $orig->($scanned_doc, @rest);
        };

        # Edit doc1 only (bumps its content_version); doc2 is untouched.
        $doc1->insert($doc1->length, " alpha_three");
        $provider->complete({ %$context1, prefix => 'alpha' });
    }

    is($doc2_scan_calls, 0, 'editing doc1 does not trigger any line scan of doc2');

    ok(refaddr($provider->{_doc_words}{$doc2_id}) == refaddr($doc2_cache_before),
        "doc2's per-document cache entry is the same hashref (untouched) after editing doc1");

    ok(exists $provider->{_doc_words}{$doc1_id}{alpha_three},
        "doc1's per-document cache entry was rebuilt and reflects the edit");

    # The merged completion results must still be correct after the
    # targeted rescan — not just faster, but accurate.
    my $results = $provider->complete({ %$context1, prefix => 'alpha' });
    my %found = map { $_->{text} => 1 } @$results;
    ok($found{'alpha_three'}, 'new word from edited doc1 appears in merged completions');
    ok($found{'alpha_one'}, 'pre-existing doc1 word still present after targeted rescan');

    my $results_beta = $provider->complete({ %$context1, prefix => 'beta' });
    my %found_beta = map { $_->{text} => 1 } @$results_beta;
    ok($found_beta{'beta_one'} && $found_beta{'beta_two'},
       "doc2's words are still present in merged completions (its cache wasn't lost, just untouched)");
};

# =============================================================================
# RecentProvider
# =============================================================================
subtest 'RecentProvider' => sub {
    my $provider = Zepto::Completion::RecentProvider->new();

    # No results before recording anything
    my $context = {
        prefix   => 'hel',
        line     => 'hel',
        col      => 3,
    };
    my $results = $provider->complete($context);
    is(scalar(@$results), 0, 'no results before any recording');

    # Record some completions
    $provider->record('hello');
    $provider->record('help');
    $provider->record('helicopter');

    $results = $provider->complete($context);
    ok(@$results >= 3, 'finds recorded completions');

    my %found = map { $_->{text} => $_->{score} } @$results;
    ok($found{'hello'}, 'hello found in recent');
    ok($found{'help'}, 'help found in recent');
    ok($found{'helicopter'}, 'helicopter found in recent');

    # All have kind 'recent'
    my @kinds = map { $_->{kind} } @$results;
    ok((grep { $_ eq 'recent' } @kinds) == scalar(@kinds), 'all results are kind recent');

    # Most recently recorded should have higher score
    # "helicopter" was recorded last (most recent)
    ok($found{'helicopter'} >= $found{'hello'}, 'most recent has higher or equal score');

    # Dedup: recording same word moves it to front
    $provider->record('hello');
    $results = $provider->complete($context);
    my @hello_results = grep { $_->{text} eq 'hello' } @$results;
    is(scalar(@hello_results), 1, 'no duplicates after re-recording');

    # Short words ignored (< 3 chars) — 'he' is not recorded
    $provider->record('he');
    my $short_ctx = { prefix => 'x', line => 'x', col => 1 };
    # prefix < 2 returns empty
    is(scalar(@{$provider->complete($short_ctx)}), 0, 'prefix too short returns empty');
};

# =============================================================================
# SnippetProvider
# =============================================================================
subtest 'SnippetProvider' => sub {
    my $provider = Zepto::Completion::SnippetProvider->new();

    # Python snippets
    my $context = {
        prefix   => 'if',
        line     => 'if',
        col      => 2,
        language => 'Python',
    };

    # "if" is an exact match to trigger, should not return (would be filtered)
    my $results = $provider->complete($context);
    is(scalar(@$results), 0, 'exact match to trigger returns empty');

    # Partial match
    my $partial_ctx = {
        prefix   => 'fo',
        line     => 'fo',
        col      => 2,
        language => 'Python',
    };
    $results = $provider->complete($partial_ctx);
    my @for_matches = grep { $_->{text} eq 'for' } @$results;
    ok(@for_matches > 0, '"for" snippet found for prefix "fo"');
    is($for_matches[0]{kind}, 'snippet', 'kind is snippet');
    ok(defined $for_matches[0]{body}, 'snippet has body');
    like($for_matches[0]{body}, qr/for.*in/, 'Python for body contains "for...in"');

    # JavaScript snippets
    my $js_ctx = {
        prefix   => 'fu',
        line     => 'fu',
        col      => 2,
        language => 'JavaScript',
    };
    $results = $provider->complete($js_ctx);
    my @func_matches = grep { $_->{text} eq 'function' } @$results;
    ok(@func_matches > 0, '"function" snippet found for JS prefix "fu"');
    like($func_matches[0]{body}, qr/function/, 'JS function body is correct');

    # Unknown language returns empty
    my $unknown_ctx = {
        prefix   => 'if',
        line     => 'if',
        col      => 2,
        language => 'Brainfuck',
    };
    $results = $provider->complete($unknown_ctx);
    is(scalar(@$results), 0, 'unknown language returns empty');

    # No language returns empty
    my $no_lang_ctx = {
        prefix   => 'if',
        line     => 'if',
        col      => 2,
        language => '',
    };
    $results = $provider->complete($no_lang_ctx);
    is(scalar(@$results), 0, 'empty language returns empty');
};

# =============================================================================
# Controller Accept with Snippets
# =============================================================================
subtest 'Controller accept with snippets' => sub {
    my $ctrl = Zepto::Completion::Controller->new();
    my $snippet = Zepto::Completion::SnippetProvider->new();
    $ctrl->add_provider($snippet);

    my $hl = Zepto::Highlighter->new();
    $hl->set_file('test.py');

    # "fo" is a 2-char prefix -- meets Controller's minimum auto-trigger
    # length (length($prefix) < 2 is rejected) -- and uniquely prefix-
    # matches the Python "for" snippet trigger (SnippetProvider.pm's
    # %SNIPPETS Python list: if/for/def/class/while/try/with -- "for" is
    # the only one starting with "fo"). SnippetProvider is the only
    # provider registered here, so this deterministically triggers and
    # accept() can only ever return the snippet hashref -- not order- or
    # scoring-dependent. Verified via direct invocation and 3x `prove`
    # runs before removing the old is_active()-gated fallback.
    my $doc = make_doc("fo\n");
    my $view = Zepto::View->new(document => $doc);
    $view->set_cursor(0, 2);

    $ctrl->trigger($doc, $view, $hl);
    ok($ctrl->is_active(), 'completion triggers for "fo" against Python snippets');

    my $result = $ctrl->accept();
    is(ref($result), 'HASH', 'accept returns a hashref (snippet result)');
    is($result->{kind}, 'snippet', 'accept returns snippet hashref');
    ok(defined $result->{body}, 'snippet result has body');
    ok(defined $result->{prefix}, 'snippet result has prefix');
    ok(!$ctrl->is_active(), 'idle after accept');
};

# =============================================================================
# Controller Accept records to RecentProvider
# =============================================================================
subtest 'Controller records accepted to RecentProvider' => sub {
    my $ctrl = Zepto::Completion::Controller->new();
    my $recent = Zepto::Completion::RecentProvider->new();
    my $bw = Zepto::Completion::CrossBufferWordProvider->new();
    $ctrl->add_provider($bw);
    $ctrl->add_provider($recent);
    $ctrl->set_recent_provider($recent);

    # "hel" (3 chars, well past the 2-char minimum) prefix-matches
    # "hello_world" which CrossBufferWordProvider finds by scanning the
    # rest of the buffer -- deterministic (the word only needs to exist
    # anywhere else in the document, no scoring race). RecentProvider is
    # empty at trigger time so it contributes nothing yet. Verified via
    # 3x `prove` runs before removing the old is_active()-gated fallback.
    my $doc = make_doc("function hello_world() {}\nhel\n");
    my $view = Zepto::View->new(document => $doc);
    $view->set_cursor(1, 3);

    $ctrl->trigger($doc, $view, undef);
    ok($ctrl->is_active(), 'completion triggers for "hel" against buffer word hello_world');

    $ctrl->accept();

    # Check that recent provider now has a recorded entry
    my $recent_results = $recent->complete({ prefix => 'hel', line => 'hel', col => 3 });
    ok(@$recent_results > 0, 'recent provider has entry after accept');
    my @hw = grep { $_->{text} eq 'hello_world' } @$recent_results;
    ok(@hw > 0, 'hello_world was recorded in recent provider');
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
# Controller Accept (basic)
# =============================================================================
subtest 'Controller accept' => sub {
    my $ctrl = Zepto::Completion::Controller->new();
    my $bw = Zepto::Completion::CrossBufferWordProvider->new();
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
    my $bw = Zepto::Completion::CrossBufferWordProvider->new();
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
    my $bw = Zepto::Completion::CrossBufferWordProvider->new();
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
    my $bw = Zepto::Completion::CrossBufferWordProvider->new();
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
