#!/usr/bin/env perl
# Comprehensive tests for Zepto::Document
use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempfile tempdir);
use lib 'lib';
use Zepto::Document;

# ============================================================================
# Construction tests
# ============================================================================
subtest 'Construction' => sub {
    my $doc = Zepto::Document->new();
    is($doc->text(), '', 'Empty document');
    is($doc->length(), 0, 'Empty length');
    ok(!$doc->is_dirty(), 'New document is clean');
    is($doc->line_ending(), "\n", 'Default line ending is LF');

    $doc = Zepto::Document->new(text => 'hello');
    is($doc->text(), 'hello', 'Document with initial text');

    $doc = Zepto::Document->new(path => '/test/file.txt');
    is($doc->path(), '/test/file.txt', 'Document with path');
    is($doc->filename(), 'file.txt', 'Filename extracted');
    is($doc->display_name(), '/test/file.txt', 'Display name is full path');

    $doc = Zepto::Document->new();
    is($doc->filename(), '[untitled]', 'Untitled filename');
    is($doc->display_name(), '[untitled]', 'Untitled display name');
};

# ============================================================================
# Basic edit operations
# ============================================================================
subtest 'Insert operations' => sub {
    my $doc = Zepto::Document->new();

    $doc->insert(0, 'hello');
    is($doc->text(), 'hello', 'Insert at start');
    ok($doc->is_dirty(), 'Document dirty after insert');

    $doc->insert(5, ' world');
    is($doc->text(), 'hello world', 'Insert at end');
};

subtest 'Delete operations' => sub {
    my $doc = Zepto::Document->new(text => 'hello world');

    my $deleted = $doc->delete(5, 1);
    is($deleted, ' ', 'Delete returns deleted text');
    is($doc->text(), 'helloworld', 'Delete from middle');
    ok($doc->is_dirty(), 'Document dirty after delete');
};

subtest 'Replace operations' => sub {
    my $doc = Zepto::Document->new(text => 'hello world');

    my $deleted = $doc->replace(0, 5, 'hi');
    is($deleted, 'hello', 'Replace returns old text');
    is($doc->text(), 'hi world', 'Replace applied');
};

# ============================================================================
# Undo/Redo tests
# ============================================================================
subtest 'Basic undo/redo' => sub {
    my $doc = Zepto::Document->new();

    ok(!$doc->can_undo(), 'Cannot undo empty');
    ok(!$doc->can_redo(), 'Cannot redo empty');

    $doc->insert(0, 'hello');
    ok($doc->can_undo(), 'Can undo after insert');

    $doc->undo();
    is($doc->text(), '', 'Undo insert');
    ok(!$doc->can_undo(), 'Cannot undo further');
    ok($doc->can_redo(), 'Can redo');

    $doc->redo();
    is($doc->text(), 'hello', 'Redo insert');
    ok($doc->can_undo(), 'Can undo again');
    ok(!$doc->can_redo(), 'Cannot redo after redo');
};

subtest 'Undo delete' => sub {
    my $doc = Zepto::Document->new(text => 'hello');
    $doc->clear_history();

    $doc->delete(0, 5);
    is($doc->text(), '', 'Text deleted');

    $doc->undo();
    is($doc->text(), 'hello', 'Undo delete restores text');

    $doc->redo();
    is($doc->text(), '', 'Redo delete');
};

subtest 'Undo replace' => sub {
    my $doc = Zepto::Document->new(text => 'hello');
    $doc->clear_history();

    $doc->replace(0, 5, 'world');
    is($doc->text(), 'world', 'Replace applied');

    $doc->undo();
    is($doc->text(), 'hello', 'Undo replace');

    $doc->redo();
    is($doc->text(), 'world', 'Redo replace');
};

subtest 'Multiple undo/redo' => sub {
    my $doc = Zepto::Document->new();

    $doc->insert(0, 'one');
    $doc->break_undo_group();
    $doc->insert(3, ' two');
    $doc->break_undo_group();
    $doc->insert(7, ' three');

    is($doc->text(), 'one two three', 'All inserts');

    $doc->undo();
    is($doc->text(), 'one two', 'Undo third');

    $doc->undo();
    is($doc->text(), 'one', 'Undo second');

    $doc->undo();
    is($doc->text(), '', 'Undo first');

    $doc->redo();
    $doc->redo();
    $doc->redo();
    is($doc->text(), 'one two three', 'Redo all');
};

subtest 'Redo cleared on new edit' => sub {
    my $doc = Zepto::Document->new(text => 'hello');
    $doc->clear_history();

    $doc->insert(5, ' world');
    $doc->undo();
    is($doc->text(), 'hello', 'Undone');
    ok($doc->can_redo(), 'Can redo');

    $doc->insert(5, ' there');
    ok(!$doc->can_redo(), 'Redo cleared after new edit');
    is($doc->text(), 'hello there', 'New edit applied');
};

# ============================================================================
# Undo grouping tests
# ============================================================================
subtest 'Undo grouping - consecutive inserts' => sub {
    my $doc = Zepto::Document->new();

    # Type characters quickly (no break between them)
    $doc->insert(0, 'h');
    $doc->insert(1, 'e');
    $doc->insert(2, 'l');
    $doc->insert(3, 'l');
    $doc->insert(4, 'o');

    is($doc->text(), 'hello', 'All chars inserted');

    # Should undo all as one group
    $doc->undo();
    is($doc->text(), '', 'Grouped insert undone at once');
};

subtest 'Undo grouping - consecutive deletes (backspace)' => sub {
    my $doc = Zepto::Document->new(text => 'hello');
    $doc->clear_history();

    # Backspace from end
    $doc->delete(4, 1);  # Delete 'o'
    $doc->delete(3, 1);  # Delete 'l'
    $doc->delete(2, 1);  # Delete 'l'

    is($doc->text(), 'he', 'Backspace deletes');

    $doc->undo();
    is($doc->text(), 'hello', 'Grouped backspace undone');
};

subtest 'Undo grouping broken by cursor move' => sub {
    my $doc = Zepto::Document->new();

    $doc->insert(0, 'ab');
    $doc->break_undo_group();  # Simulates cursor move
    $doc->insert(2, 'cd');

    is($doc->text(), 'abcd', 'Both inserted');

    $doc->undo();
    is($doc->text(), 'ab', 'Second group undone');

    $doc->undo();
    is($doc->text(), '', 'First group undone');
};

# ============================================================================
# Dirty tracking tests
# ============================================================================
subtest 'Dirty tracking' => sub {
    my $doc = Zepto::Document->new();
    ok(!$doc->is_dirty(), 'New doc clean');

    $doc->insert(0, 'x');
    ok($doc->is_dirty(), 'Dirty after edit');

    $doc->mark_clean();
    ok(!$doc->is_dirty(), 'Clean after mark_clean');

    $doc->insert(1, 'y');
    ok($doc->is_dirty(), 'Dirty again');

    $doc->undo();
    # After undoing everything, should be clean
    # But we only undid one action, and there was a mark_clean in between
    # So it depends on implementation - let's check current behavior
};

subtest 'Dirty tracking with undo' => sub {
    my $doc = Zepto::Document->new();

    $doc->insert(0, 'hello');
    ok($doc->is_dirty(), 'Dirty after insert');

    $doc->undo();
    ok(!$doc->is_dirty(), 'Clean after undoing all');

    $doc->redo();
    ok($doc->is_dirty(), 'Dirty after redo');
};

# ============================================================================
# File I/O tests
# ============================================================================
subtest 'Save and load' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $path = "$dir/test.txt";

    my $doc = Zepto::Document->new(text => "line1\nline2\nline3");
    $doc->save($path);

    ok(-f $path, 'File created');
    ok(!$doc->is_dirty(), 'Clean after save');
    is($doc->path(), $path, 'Path set after save');

    my $loaded = Zepto::Document->load($path);
    is($loaded->text(), "line1\nline2\nline3", 'Content loaded');
    is($loaded->line_ending(), "\n", 'LF line ending detected');
    ok(!$loaded->is_dirty(), 'Loaded doc is clean');
};

subtest 'Save and load with CRLF' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $path = "$dir/crlf.txt";

    my $doc = Zepto::Document->new(text => "line1\nline2");
    $doc->set_line_ending("\r\n");
    $doc->save($path);

    # Read raw file
    open my $fh, '<:raw', $path;
    local $/;
    my $raw = <$fh>;
    close $fh;

    like($raw, qr/\r\n/, 'CRLF written to file');

    my $loaded = Zepto::Document->load($path);
    is($loaded->text(), "line1\nline2", 'CRLF normalized to LF on load');
    is($loaded->line_ending(), "\r\n", 'CRLF detected');
};

subtest 'Save preserves permissions' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $path = "$dir/perms.txt";

    my $doc = Zepto::Document->new(text => 'test');
    $doc->{permissions} = 0644;
    $doc->save($path);

    my $mode = (stat($path))[2] & 07777;
    is($mode, 0644, 'Permissions preserved');
};

subtest 'Atomic save' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $path = "$dir/atomic.txt";

    # Create initial file
    my $doc = Zepto::Document->new(text => 'initial');
    $doc->save($path);

    # Modify and save again
    $doc->insert($doc->length(), ' modified');
    $doc->save($path);

    is($doc->text(), 'initial modified', 'Text updated');

    # Verify no temp file left behind
    my @files = glob("$dir/*");
    is(scalar(@files), 1, 'No temp files left');
};

# ============================================================================
# Buffer delegation tests
# ============================================================================
subtest 'Buffer delegation' => sub {
    my $doc = Zepto::Document->new(text => "line1\nline2\nline3");

    is($doc->line_count(), 3, 'line_count delegated');
    is($doc->get_line_content(0), 'line1', 'get_line_content delegated');
    is($doc->line_length(1), 5, 'line_length delegated');
    is($doc->get_text(0, 5), 'line1', 'get_text delegated');

    my ($line, $col) = $doc->offset_to_line_col(7);
    is($line, 1, 'offset_to_line_col line');
    is($col, 1, 'offset_to_line_col col');

    my $offset = $doc->line_col_to_offset(2, 3);
    is($offset, 15, 'line_col_to_offset');
};

# ============================================================================
# Edge cases
# ============================================================================
subtest 'Edge cases' => sub {
    # Empty file operations
    my $doc = Zepto::Document->new();
    $doc->undo();  # Should not crash
    $doc->redo();  # Should not crash

    # Delete nothing
    my $deleted = $doc->delete(0, 0);
    is($deleted, '', 'Delete nothing');

    # Insert empty
    $doc->insert(0, '');
    is($doc->text(), '', 'Insert empty');
    ok(!$doc->is_dirty(), 'Still clean after empty ops');
};

subtest 'Unicode content' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $path = "$dir/unicode.txt";

    my $doc = Zepto::Document->new(text => "日本語\nこんにちは");
    $doc->save($path);

    my $loaded = Zepto::Document->load($path);
    is($loaded->text(), "日本語\nこんにちは", 'Unicode preserved');
    is($loaded->line_count(), 2, 'Unicode lines counted');
};

# ============================================================================
# Performance sanity
# ============================================================================
subtest 'Many edits performance' => sub {
    my $doc = Zepto::Document->new();

    # Many small edits
    for my $i (1..100) {
        $doc->insert($doc->length(), "x");
        $doc->break_undo_group() if $i % 10 == 0;
    }

    is($doc->length(), 100, '100 inserts');
    ok($doc->can_undo(), 'Can undo');

    # Undo all
    while ($doc->can_undo()) {
        $doc->undo();
    }

    is($doc->text(), '', 'All undone');
};

done_testing();
