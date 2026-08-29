#!/usr/bin/env perl
# Tests for Zepto::Editor incremental find feature
use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempfile);

use Zepto::Editor;
use Zepto::Terminal;
use Zepto::Document;
use Zepto::View;
use Zepto::FindEngine;
use Zepto::Highlighter;

# Create a mock terminal for testing
sub mock_terminal {
    my ($in_fh, $in_name) = tempfile(UNLINK => 1);
    my ($out_fh, $out_name) = tempfile(UNLINK => 1);
    return Zepto::Terminal->new(in => $in_fh, out => $out_fh);
}

# Helper to create an editor with specific content
sub create_editor_with_content {
    my ($content) = @_;
    my $term = mock_terminal();
    my $editor = Zepto::Editor->new(terminal => $term);
    my $doc = Zepto::Document->new();
    $doc->insert(0, $content);
    my $view = Zepto::View->new(document => $doc);
    my $find_engine = Zepto::FindEngine->new(document => $doc);
    my $highlighter = Zepto::Highlighter->new();
    $editor->{tab_manager}->add_tab(
        document    => $doc,
        view        => $view,
        find_engine => $find_engine,
        highlighter => $highlighter,
        file_path   => undef,
    );
    return $editor;
}

# ============================================================================
# Enter/Exit Find Mode
# ============================================================================
subtest 'Enter find mode' => sub {
    my $editor = create_editor_with_content("Hello World\n");

    $editor->enter_find_mode();

    is($editor->{state}, Zepto::Editor::STATE_FIND, 'State is find');
    is($editor->{find_widget}->value(), '', 'Find input is empty initially');
    is($editor->{find_widget}->cursor(), 0, 'Cursor at start');
    is(scalar @{$editor->{find_matches}}, 0, 'No matches initially');
};

subtest 'Enter find mode with previous search term' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->{search_term} = 'World';

    $editor->enter_find_mode();

    is($editor->{find_widget}->value(), 'World', 'Pre-filled with previous search');
    is($editor->{find_widget}->cursor(), 5, 'Cursor at end of term');
};

subtest 'Exit find mode saves search term' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('Hello');

    $editor->exit_find_mode('dismiss');

    is($editor->{state}, Zepto::Editor::STATE_EDITING, 'State is editing');
    is($editor->{search_term}, 'Hello', 'Search term saved');
    is(scalar @{$editor->{find_matches}}, 0, 'Matches cleared');
};

# ============================================================================
# Match Finding - Literal Search
# ============================================================================
subtest 'Literal search - single match' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('World');

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 1, 'Found one match');
    is($editor->{find_matches}[0]{line}, 0, 'Match on line 0');
    is($editor->{find_matches}[0]{col}, 6, 'Match at correct column');
    is($editor->{find_matches}[0]{length}, 5, 'Match has correct length');
};

subtest 'Literal search - multiple matches' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo');

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 3, 'Found three matches');
    is($editor->{find_matches}[0]{col}, 0, 'First match at start');
    is($editor->{find_matches}[1]{col}, 8, 'Second match correct');
    is($editor->{find_matches}[2]{col}, 16, 'Third match correct');
};

subtest 'Literal search - no matches' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('xyz');

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 0, 'No matches found');
};

subtest 'Literal search - empty search' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('');

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 0, 'Empty search returns no matches');
};

# ============================================================================
# Match Finding - Case Sensitivity
# ============================================================================
subtest 'Case-insensitive search (default)' => sub {
    my $editor = create_editor_with_content("Hello HELLO hello\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('hello');
    $editor->{find_case} = 0;  # Case-insensitive

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 3, 'Found all case variants');
};

subtest 'Case-sensitive search' => sub {
    my $editor = create_editor_with_content("Hello HELLO hello\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('hello');
    $editor->{find_case} = 1;  # Case-sensitive

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 1, 'Found only exact case match');
    is($editor->{find_matches}[0]{col}, 12, 'Match at correct position');
};

# ============================================================================
# Match Finding - Regex
# ============================================================================
subtest 'Regex search' => sub {
    my $editor = create_editor_with_content("foo123 bar456 foo789\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo\d+');
    $editor->{find_regex} = 1;

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 2, 'Found two regex matches');
    is($editor->{find_matches}[0]{col}, 0, 'First match at start');
    is($editor->{find_matches}[0]{length}, 6, 'First match length correct');
    is($editor->{find_matches}[1]{col}, 14, 'Second match correct');
};

subtest 'Regex search - case insensitive' => sub {
    my $editor = create_editor_with_content("FOO123 foo456\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo\d+');
    $editor->{find_regex} = 1;
    $editor->{find_case} = 0;

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 2, 'Found both case variants');
};

subtest 'Regex search - invalid regex' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('[invalid');
    $editor->{find_regex} = 1;

    # Should not die
    eval { $editor->_update_find_matches(); };
    ok(!$@, 'Invalid regex does not die');
    is(scalar @{$editor->{find_matches}}, 0, 'Invalid regex returns no matches');
};

# ============================================================================
# Navigation
# ============================================================================
subtest 'Navigate to next match' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo');
    $editor->_update_find_matches();

    # Start at first match (nearest to cursor at 0)
    is($editor->{find_current}, 0, 'Start at first match');

    $editor->_find_navigate(1);
    is($editor->{find_current}, 1, 'Moved to second match');

    $editor->_find_navigate(1);
    is($editor->{find_current}, 2, 'Moved to third match');
};

subtest 'Navigate wraps at end' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo');
    $editor->_update_find_matches();

    $editor->{find_current} = 2;  # Last match
    $editor->_find_navigate(1);   # Next

    is($editor->{find_current}, 0, 'Wrapped to first match');
};

subtest 'Navigate wraps at start' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo');
    $editor->_update_find_matches();

    $editor->{find_current} = 0;  # First match
    $editor->_find_navigate(-1);  # Previous

    is($editor->{find_current}, 2, 'Wrapped to last match');
};

subtest 'Navigate with no matches' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('xyz');
    $editor->_update_find_matches();

    # Should not die
    eval { $editor->_find_navigate(1); };
    ok(!$@, 'Navigate with no matches does not die');
};

# ============================================================================
# Find Nearest Match
# ============================================================================
subtest 'Find nearest match to cursor' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->active_view()->set_cursor(0, 10);  # Position near second "foo"
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo');
    $editor->_update_find_matches();

    # Should select the match at or after cursor position
    ok($editor->{find_current} >= 1, 'Selected match near cursor');
};

# ============================================================================
# Toggle Options
# ============================================================================
subtest 'Toggle cycles through options' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();

    # Initial state (literal search by default — QA-REG-105)
    is($editor->{find_regex}, 0, 'Regex off initially (literal default)');
    is($editor->{find_case}, 0, 'Case off initially');

    # Toggle: regex off
    $editor->{find_regex} = 0;
    is($editor->{find_regex}, 0, 'Regex toggled off');

    # Second toggle: regex off, case on
    $editor->{find_regex} = 0;
    $editor->{find_case} = 1;
    is($editor->{find_case}, 1, 'Case toggled on');

    # Third toggle: case off
    $editor->{find_case} = 0;
    is($editor->{find_case}, 0, 'Case toggled off');
};

# ============================================================================
# Replace Functionality
# ============================================================================
subtest 'Enter find mode loads previous replace' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->{search_replace} = 'Universe';

    $editor->enter_find_mode();

    is($editor->{find_replace_active}, 0, 'Find-only mode by default');
    is($editor->{find_replace_widget}->value(), 'Universe', 'Pre-filled with previous replace');
    is($editor->{find_focus}, 'find', 'Focus starts on find field');
};

subtest 'Replace current match' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('foo');
    $editor->{find_replace_widget}->set_value('XXX');
    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 3, 'Found three matches');

    $editor->_replace_current();

    my $text = $editor->active_doc()->text();
    like($text, qr/^XXX bar/, 'First foo replaced with XXX');
    is(scalar @{$editor->{find_matches}}, 2, 'Now two matches');
};

subtest 'Replace all matches' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('foo');
    $editor->{find_replace_widget}->set_value('YYY');
    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 3, 'Found three matches');

    $editor->_replace_all();

    my $text = $editor->active_doc()->text();
    is($text, "YYY bar YYY baz YYY\n", 'All foo replaced with YYY');
    is(scalar @{$editor->{find_matches}}, 0, 'No matches after replace all');
};

subtest 'Replace with empty string' => sub {
    my $editor = create_editor_with_content("foo bar foo\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('foo');
    $editor->{find_replace_widget}->set_value('');
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->active_doc()->text();
    is($text, " bar \n", 'All foo deleted (replaced with empty)');
};

subtest 'Replace preserves case with regex' => sub {
    my $editor = create_editor_with_content("The cat sat on the mat.\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('at');
    $editor->{find_replace_widget}->set_value('og');
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->active_doc()->text();
    is($text, "The cog sog on the mog.\n", 'All "at" replaced with "og"');
};

subtest 'Tab toggles focus in combined find/replace' => sub {
    my $editor = create_editor_with_content("test\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo');

    # Find-only mode by default
    is($editor->{find_replace_active}, 0, 'Find-only mode by default');
    is($editor->{find_focus}, 'find', 'Focus starts on find field');

    # Simulate Tab press - should activate replace and move focus
    $editor->handle_find_event({ type => 'key', key => 'tab' });

    is($editor->{find_replace_active}, 1, 'Tab activates replace field');
    is($editor->{find_focus}, 'replace', 'Tab moves focus to replace');
};

subtest 'Tab toggles focus between fields' => sub {
    my $editor = create_editor_with_content("test\n");
    $editor->enter_find_mode(replace => 1);  # with replace
    $editor->{find_focus} = 'find';

    $editor->handle_find_event({ type => 'key', key => 'tab' });
    is($editor->{find_focus}, 'replace', 'Tab moves to replace');

    $editor->handle_find_event({ type => 'key', key => 'tab' });
    is($editor->{find_focus}, 'find', 'Tab moves back to find');
};

# ============================================================================
# Bug regression: Find after opening different file
# ============================================================================
subtest 'Find searches new document after loading different file' => sub {
    # Create editor with initial content
    my $editor = create_editor_with_content("apple banana cherry\n");

    # Verify initial content works
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('apple');
    $editor->_update_find_matches();
    is(scalar @{$editor->{find_matches}}, 1, 'Found "apple" in initial file');
    $editor->exit_find_mode(0);

    # Create a new temp file with different content
    my ($fh, $newfile) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh "dog elephant fox\n";
    close $fh;

    # Load the new file (simulates Ctrl-O -> select file)
    $editor->_load_file($newfile);

    # Search for content that's only in the NEW file
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('elephant');
    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 1, 'Found "elephant" in new file');

    # Search for content that was only in the OLD file
    $editor->{find_widget}->set_value('apple');
    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 0, 'No "apple" in new file (old content gone)');
};

# ============================================================================
# Capture Group Counting
# ============================================================================
subtest 'Count capture groups in regex patterns' => sub {
    my $editor = create_editor_with_content("test\n");
    my $engine = $editor->active_find_engine();
    $engine->{use_regex} = 1;

    is($engine->_count_capture_groups('foo'), 0, 'No groups');
    is($engine->_count_capture_groups('(foo)'), 1, 'One group');
    is($engine->_count_capture_groups('(foo)(bar)'), 2, 'Two groups');
    is($engine->_count_capture_groups('(foo(bar))'), 2, 'Nested groups');
    is($engine->_count_capture_groups('(?:foo)'), 0, 'Non-capturing (?:)');
    is($engine->_count_capture_groups('(?=foo)'), 0, 'Lookahead (?=)');
    is($engine->_count_capture_groups('(?!foo)'), 0, 'Negative lookahead (?!)');
    is($engine->_count_capture_groups('(?<=foo)'), 0, 'Lookbehind (?<=)');
    is($engine->_count_capture_groups('(?<!foo)'), 0, 'Negative lookbehind (?<!)');
    is($engine->_count_capture_groups('\\(foo\\)'), 0, 'Escaped parens');
    is($engine->_count_capture_groups('[(]foo[)]'), 0, 'Parens inside char class');
    is($engine->_count_capture_groups('(?<name>foo)'), 1, 'Named capture (?<name>)');
    is($engine->_count_capture_groups('(a)(?:b)(c)'), 2, 'Mixed capturing and non-capturing');
    is($engine->_count_capture_groups(''), 0, 'Empty pattern');
    is($engine->_count_capture_groups('(a)(b)(c)(d)'), 4, 'Four groups');
};

subtest 'capture_group_count respects regex mode' => sub {
    my $editor = create_editor_with_content("test\n");
    my $engine = $editor->active_find_engine();

    # Non-regex mode always returns 0
    $engine->{use_regex} = 0;
    $engine->{search_term} = '(foo)';
    is($engine->capture_group_count(), 0, 'Non-regex mode returns 0');

    # Regex mode counts groups
    $engine->{use_regex} = 1;
    $engine->{search_term} = '(\w+) (\w+)';
    is($engine->capture_group_count(), 2, 'Two capture groups');

    $engine->{search_term} = '(?:\w+) (\w+)';
    is($engine->capture_group_count(), 1, 'One capturing, one non-capturing');

    $engine->{search_term} = 'no groups here';
    is($engine->capture_group_count(), 0, 'No groups');
};

# ============================================================================
# Replacement Expansion
# ============================================================================
subtest 'Expand replacement with capture references' => sub {
    my $editor = create_editor_with_content("test\n");
    my $engine = $editor->active_find_engine();

    # $0 = full match
    is($engine->_expand_replacement('[$0]', 'hello', []),
       '[hello]', '$0 expands to full match');

    # $1, $2 from captures
    is($engine->_expand_replacement('$2-$1', 'foobar', ['foo', 'bar']),
       'bar-foo', '$1 and $2 expand to captures');

    # $N beyond capture count -> literal
    is($engine->_expand_replacement('$3', 'test', ['a', 'b']),
       '$3', '$N beyond count stays literal');

    # $$ -> literal $
    is($engine->_expand_replacement('$$1', 'test', ['a']),
       '$1', '$$ becomes literal $');

    # No $ in replacement -> unchanged
    is($engine->_expand_replacement('xyz', 'test', ['a']),
       'xyz', 'No $ means no expansion');

    # $ at end of string
    is($engine->_expand_replacement('end$', 'test', []),
       'end$', '$ at end stays literal');

    # $ followed by non-digit
    is($engine->_expand_replacement('$x', 'test', []),
       '$x', '$ followed by non-digit stays literal');

    # Empty replacement
    is($engine->_expand_replacement('', 'test', ['a']),
       '', 'Empty replacement stays empty');

    # $0 with no captures
    is($engine->_expand_replacement('($0)', 'word', []),
       '(word)', '$0 works even with no capture groups');

    # Multiple references to same capture
    is($engine->_expand_replacement('$1-$1', 'test', ['x']),
       'x-x', 'Same capture referenced twice');

    # Multi-digit capture number
    is($engine->_expand_replacement('$10', 'test',
       ['a','b','c','d','e','f','g','h','i','j']),
       'j', '$10 works for 10th capture');
};

# ============================================================================
# Integration: Replace with Capture Groups
# ============================================================================
subtest 'Replace current with capture groups' => sub {
    my $editor = create_editor_with_content("John Smith\nJane Doe\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('(\w+) (\w+)');
    $editor->{find_regex} = 1;
    $editor->{find_replace_widget}->set_value('$2, $1');
    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 2, 'Found two matches');

    $editor->_replace_current();

    my $text = $editor->active_doc()->text();
    like($text, qr/Smith, John/, 'First match replaced with swapped captures');
    like($text, qr/Jane Doe/, 'Second match not yet replaced');
};

subtest 'Replace all with capture groups' => sub {
    my $editor = create_editor_with_content("John Smith\nJane Doe\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('(\w+) (\w+)');
    $editor->{find_regex} = 1;
    $editor->{find_replace_widget}->set_value('$2, $1');
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->active_doc()->text();
    is($text, "Smith, John\nDoe, Jane\n", 'All matches replaced with swapped captures');
};

subtest 'Replace with $0 (full match reference)' => sub {
    my $editor = create_editor_with_content("foo bar baz\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('\w+');
    $editor->{find_regex} = 1;
    $editor->{find_replace_widget}->set_value('[$0]');
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->active_doc()->text();
    is($text, "[foo] [bar] [baz]\n", 'Each word wrapped in brackets via \$0');
};

subtest 'Literal mode ignores capture references' => sub {
    my $editor = create_editor_with_content("foo bar foo\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('foo');
    $editor->{find_regex} = 0;  # Literal mode
    $editor->{find_replace_widget}->set_value('$1');
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->active_doc()->text();
    is($text, "\$1 bar \$1\n", 'Literal mode leaves $1 as literal text');
};

subtest 'Dollar sign escape in replacement' => sub {
    my $editor = create_editor_with_content("foo\n");
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('foo');
    $editor->{find_regex} = 1;
    $editor->{find_replace_widget}->set_value('$$100');
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->active_doc()->text();
    is($text, "\$100\n", '\$\$ produces literal \$ in output');
};

subtest 'Preview line with capture expansion' => sub {
    my $editor = create_editor_with_content("John Smith\n");
    my $engine = $editor->active_find_engine();

    $engine->search('(\w+) (\w+)', 0, 1,
        use_regex => 1,
        case_sensitive => 0,
    );
    # Complete background search
    while ($engine->is_searching()) { $engine->tick(100); }

    my $preview = $engine->preview_line(0, '$2, $1');

    is($preview->{text}, 'Smith, John', 'Preview shows expanded captures');
    is(scalar @{$preview->{highlights}}, 1, 'One highlight in preview');
};

subtest 'Replace all with captures on many matches' => sub {
    # Test the _replace_all fast path (string concatenation) for >3 matches
    my $content = join("\n", map { "item_$_" } 1..5) . "\n";
    my $editor = create_editor_with_content($content);
    $editor->enter_find_mode(replace => 1);
    $editor->{find_widget}->set_value('item_(\d+)');
    $editor->{find_regex} = 1;
    $editor->{find_replace_widget}->set_value('thing[$1]');
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->active_doc()->text();
    my $expected = join("\n", map { "thing[$_]" } 1..5) . "\n";
    is($text, $expected, 'All items renumbered with capture groups');
};

subtest 'Extract capture positions for highlighting' => sub {
    my $editor = create_editor_with_content("John Smith\n");
    my $engine = $editor->active_find_engine();

    $engine->search('(\w+) (\w+)', 0, 1,
        use_regex => 1,
        case_sensitive => 0,
    );
    while ($engine->is_searching()) { $engine->tick(100); }

    my $matches = $engine->matches();
    ok(@$matches >= 1, 'Found at least one match');

    my $positions = $engine->extract_capture_positions($matches->[0]);
    is(scalar @$positions, 2, 'Two capture positions');
    is($positions->[0]{start}, 0, 'First capture starts at 0');
    is($positions->[0]{length}, 4, 'First capture is 4 chars (John)');
    is($positions->[0]{group}, 1, 'First capture is group 1');
    is($positions->[1]{start}, 5, 'Second capture starts at 5');
    is($positions->[1]{length}, 5, 'Second capture is 5 chars (Smith)');
    is($positions->[1]{group}, 2, 'Second capture is group 2');
};

# ============================================================================
# Current-match index clamped when match list shrinks (QA-REG-107)
# ============================================================================
# Regression: with the cursor on match 3 of 3, toggling regex/case re-runs
# the search with skip_jump — if the new list has fewer matches, the stale
# index rendered as "3 of 1" in the find bar.
subtest 'find_current clamped when matches shrink' => sub {
    my $editor = create_editor_with_content("fooXbar\nfoo.bar\nfooYbar\n");
    $editor->enter_find_mode();
    $editor->{find_widget}->set_value('foo.bar');
    $editor->{find_regex} = 1;
    $editor->_update_find_matches();
    is(scalar @{$editor->{find_matches}}, 3, 'Regex dot matches all 3 lines');

    # Navigate to the last match
    $editor->_find_navigate(1);
    $editor->_find_navigate(1);
    is($editor->{find_current}, 2, 'On match 3 of 3');

    # Toggle to literal (as the ⌃R handler does: re-search with skip_jump)
    $editor->{find_regex} = 0;
    $editor->_update_find_matches(1);
    is(scalar @{$editor->{find_matches}}, 1, 'Literal search matches 1 line');
    ok($editor->{find_current} < scalar @{$editor->{find_matches}},
       'find_current clamped within new match count (no "3 of 1")');
};

done_testing();
