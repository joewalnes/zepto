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
    $editor->{document} = Zepto::Document->new();
    $editor->{document}->insert(0, $content);
    $editor->{view} = Zepto::View->new(document => $editor->{document});
    # Create find engine for async search
    $editor->{find_engine} = Zepto::FindEngine->new(
        document => $editor->{document},
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
    is($editor->{find_input}, '', 'Find input is empty initially');
    is($editor->{find_input_cursor}, 0, 'Cursor at start');
    is(scalar @{$editor->{find_matches}}, 0, 'No matches initially');
};

subtest 'Enter find mode with previous search term' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->{search_term} = 'World';

    $editor->enter_find_mode();

    is($editor->{find_input}, 'World', 'Pre-filled with previous search');
    is($editor->{find_input_cursor}, 5, 'Cursor at end of term');
};

subtest 'Exit find mode saves search term' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_input} = 'Hello';

    $editor->exit_find_mode(1);

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
    $editor->{find_input} = 'World';

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 1, 'Found one match');
    is($editor->{find_matches}[0]{line}, 0, 'Match on line 0');
    is($editor->{find_matches}[0]{col}, 6, 'Match at correct column');
    is($editor->{find_matches}[0]{length}, 5, 'Match has correct length');
};

subtest 'Literal search - multiple matches' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode();
    $editor->{find_input} = 'foo';

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 3, 'Found three matches');
    is($editor->{find_matches}[0]{col}, 0, 'First match at start');
    is($editor->{find_matches}[1]{col}, 8, 'Second match correct');
    is($editor->{find_matches}[2]{col}, 16, 'Third match correct');
};

subtest 'Literal search - no matches' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_input} = 'xyz';

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 0, 'No matches found');
};

subtest 'Literal search - empty search' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_input} = '';

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 0, 'Empty search returns no matches');
};

# ============================================================================
# Match Finding - Case Sensitivity
# ============================================================================
subtest 'Case-insensitive search (default)' => sub {
    my $editor = create_editor_with_content("Hello HELLO hello\n");
    $editor->enter_find_mode();
    $editor->{find_input} = 'hello';
    $editor->{find_case} = 0;  # Case-insensitive

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 3, 'Found all case variants');
};

subtest 'Case-sensitive search' => sub {
    my $editor = create_editor_with_content("Hello HELLO hello\n");
    $editor->enter_find_mode();
    $editor->{find_input} = 'hello';
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
    $editor->{find_input} = 'foo\d+';
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
    $editor->{find_input} = 'foo\d+';
    $editor->{find_regex} = 1;
    $editor->{find_case} = 0;

    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 2, 'Found both case variants');
};

subtest 'Regex search - invalid regex' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_input} = '[invalid';
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
    $editor->{find_input} = 'foo';
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
    $editor->{find_input} = 'foo';
    $editor->_update_find_matches();

    $editor->{find_current} = 2;  # Last match
    $editor->_find_navigate(1);   # Next

    is($editor->{find_current}, 0, 'Wrapped to first match');
};

subtest 'Navigate wraps at start' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode();
    $editor->{find_input} = 'foo';
    $editor->_update_find_matches();

    $editor->{find_current} = 0;  # First match
    $editor->_find_navigate(-1);  # Previous

    is($editor->{find_current}, 2, 'Wrapped to last match');
};

subtest 'Navigate with no matches' => sub {
    my $editor = create_editor_with_content("Hello World\n");
    $editor->enter_find_mode();
    $editor->{find_input} = 'xyz';
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
    $editor->{view}->set_cursor(0, 10);  # Position near second "foo"
    $editor->enter_find_mode();
    $editor->{find_input} = 'foo';
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

    # Initial state
    is($editor->{find_regex}, 0, 'Regex off initially');
    is($editor->{find_case}, 0, 'Case off initially');

    # Simulate tab key to toggle (from handle_find_event logic)
    # First toggle: regex on
    $editor->{find_regex} = 1;
    is($editor->{find_regex}, 1, 'Regex toggled on');

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

    is($editor->{find_replace_active}, 1, 'Replace is always active (unified find/replace)');
    is($editor->{find_replace_input}, 'Universe', 'Pre-filled with previous replace');
    is($editor->{find_focus}, 'find', 'Focus starts on find field');
};

subtest 'Replace current match' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode(1);
    $editor->{find_input} = 'foo';
    $editor->{find_replace_input} = 'XXX';
    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 3, 'Found three matches');

    $editor->_replace_current();

    my $text = $editor->{document}->text();
    like($text, qr/^XXX bar/, 'First foo replaced with XXX');
    is(scalar @{$editor->{find_matches}}, 2, 'Now two matches');
};

subtest 'Replace all matches' => sub {
    my $editor = create_editor_with_content("foo bar foo baz foo\n");
    $editor->enter_find_mode(1);
    $editor->{find_input} = 'foo';
    $editor->{find_replace_input} = 'YYY';
    $editor->_update_find_matches();

    is(scalar @{$editor->{find_matches}}, 3, 'Found three matches');

    $editor->_replace_all();

    my $text = $editor->{document}->text();
    is($text, "YYY bar YYY baz YYY\n", 'All foo replaced with YYY');
    is(scalar @{$editor->{find_matches}}, 0, 'No matches after replace all');
};

subtest 'Replace with empty string' => sub {
    my $editor = create_editor_with_content("foo bar foo\n");
    $editor->enter_find_mode(1);
    $editor->{find_input} = 'foo';
    $editor->{find_replace_input} = '';
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->{document}->text();
    is($text, " bar \n", 'All foo deleted (replaced with empty)');
};

subtest 'Replace preserves case with regex' => sub {
    my $editor = create_editor_with_content("The cat sat on the mat.\n");
    $editor->enter_find_mode(1);
    $editor->{find_input} = 'at';
    $editor->{find_replace_input} = 'og';
    $editor->_update_find_matches();

    $editor->_replace_all();

    my $text = $editor->{document}->text();
    is($text, "The cog sog on the mog.\n", 'All "at" replaced with "og"');
};

subtest 'Tab toggles focus in combined find/replace' => sub {
    my $editor = create_editor_with_content("test\n");
    $editor->enter_find_mode();
    $editor->{find_input} = 'foo';

    # Replace is always active now (unified find/replace)
    is($editor->{find_replace_active}, 1, 'Replace always active');
    is($editor->{find_focus}, 'find', 'Focus starts on find field');

    # Simulate Tab press - should move to replace
    $editor->handle_find_event({ type => 'key', key => 'tab' });

    is($editor->{find_focus}, 'replace', 'Tab moves focus to replace');
};

subtest 'Tab toggles focus between fields' => sub {
    my $editor = create_editor_with_content("test\n");
    $editor->enter_find_mode(1);  # with replace
    $editor->{find_focus} = 'find';

    $editor->handle_find_event({ type => 'key', key => 'tab' });
    is($editor->{find_focus}, 'replace', 'Tab moves to replace');

    $editor->handle_find_event({ type => 'key', key => 'tab' });
    is($editor->{find_focus}, 'find', 'Tab moves back to find');
};

done_testing();
