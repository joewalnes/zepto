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

subtest 'Nested begin/end_undo_group is reentrancy-safe' => sub {
    # Reproduces the latent bug from bugs.md "Scorecard audit round 3":
    # begin_undo_group() used to no-op whenever a group was already open,
    # and end_undo_group() unconditionally cleared _undo_group regardless
    # of nesting depth. So an inner begin/end pair nested inside an outer
    # one would flush and clear the *shared* group array as soon as the
    # inner end_undo_group() ran, and the outer end_undo_group() would
    # then find _undo_group already undef and silently do nothing —
    # splitting what should be one atomic undo group into two, and
    # dropping the outer group's "closing" bookkeeping (redo/dirty/
    # last_edit_type) entirely.
    my $doc = Zepto::Document->new();

    $doc->begin_undo_group();      # outer group opens
    $doc->insert(0, 'A');
    $doc->begin_undo_group();      # nested (inner) group
    $doc->insert(1, 'B');
    $doc->end_undo_group();        # inner end — must NOT flush the outer group
    $doc->insert(2, 'C');          # still part of the still-open outer group
    $doc->end_undo_group();        # outer end — flushes A+B+C as ONE group

    is($doc->text(), 'ABC', 'All three edits applied');
    is(scalar(@{$doc->{undo_stack}}), 1,
        'A, B, and C were flushed as a single grouped undo entry, not split by the inner end');

    $doc->undo();
    is($doc->text(), '', 'A single undo() reverts the entire nested group atomically');
    ok(!$doc->can_undo(), 'Nothing left to undo after one undo() call');

    $doc->redo();
    is($doc->text(), 'ABC', 'A single redo() restores the entire nested group atomically');
};

subtest 'Doubly-nested begin/end_undo_group (depth 3) is reentrancy-safe' => sub {
    my $doc = Zepto::Document->new();

    $doc->begin_undo_group();
    $doc->insert(0, 'X');
    $doc->begin_undo_group();
    $doc->insert(1, 'Y');
    $doc->begin_undo_group();
    $doc->insert(2, 'Z');
    $doc->end_undo_group();   # depth 3->2, no flush
    $doc->end_undo_group();   # depth 2->1, no flush
    $doc->end_undo_group();   # depth 1->0, flush

    is($doc->text(), 'XYZ', 'All three edits applied');
    is(scalar(@{$doc->{undo_stack}}), 1, 'Triple-nested group flushed as a single undo entry');

    $doc->undo();
    is($doc->text(), '', 'Single undo reverts the whole triple-nested group');
};

subtest 'Unbalanced end_undo_group without begin is a safe no-op' => sub {
    my $doc = Zepto::Document->new();
    $doc->insert(0, 'z');
    $doc->end_undo_group();  # no matching begin — must not throw or corrupt state
    is($doc->text(), 'z', 'Stray end_undo_group did not affect document state');
    ok($doc->can_undo(), 'Normal undo history still intact after stray end_undo_group');
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

# ============================================================================
# External file change detection
# ============================================================================

subtest 'capture_file_mtime records mtime on load' => sub {
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh "original\n";
    close $fh;

    my $doc = Zepto::Document->load($filename);
    ok(defined $doc->{_file_mtime}, 'mtime captured after load');
    ok(!$doc->check_external_changes(), 'No external changes immediately after load');
};

subtest 'check_external_changes detects modifications' => sub {
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh "original\n";
    close $fh;

    my $doc = Zepto::Document->load($filename);

    # Modify file externally (ensure different mtime by sleeping)
    sleep 1;
    open my $wfh, '>', $filename;
    print $wfh "modified\n";
    close $wfh;

    ok($doc->check_external_changes(), 'External change detected after file modification');
};

subtest 'check_external_changes returns 0 for untitled docs' => sub {
    my $doc = Zepto::Document->new(text => 'hello');
    ok(!$doc->check_external_changes(), 'No external changes for untitled document');
};

subtest 'reload_from_disk replaces buffer content' => sub {
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh "version 1\n";
    close $fh;

    my $doc = Zepto::Document->load($filename);
    is($doc->text(), 'version 1', 'Initial content');

    # Modify file externally
    sleep 1;
    open my $wfh, '>', $filename;
    print $wfh "version 2\n";
    close $wfh;

    ok($doc->check_external_changes(), 'Change detected');
    $doc->reload_from_disk();

    is($doc->text(), 'version 2', 'Content reloaded');
    ok(!$doc->is_dirty(), 'Document is clean after reload');
    ok(!$doc->check_external_changes(), 'No external changes after reload');
};

subtest 'reload_from_disk clears undo/redo stacks' => sub {
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh "original\n";
    close $fh;

    my $doc = Zepto::Document->load($filename);
    $doc->insert(0, 'edit ');
    ok($doc->can_undo(), 'Can undo after edit');

    sleep 1;
    open my $wfh, '>', $filename;
    print $wfh "replaced\n";
    close $wfh;

    $doc->reload_from_disk();
    ok(!$doc->can_undo(), 'Undo stack cleared after reload');
};

subtest 'save updates mtime so check_external_changes returns false' => sub {
    my ($fh, $filename) = tempfile(UNLINK => 1, SUFFIX => '.txt');
    print $fh "original\n";
    close $fh;

    my $doc = Zepto::Document->load($filename);
    $doc->insert(0, 'edit ');
    $doc->save();

    ok(!$doc->check_external_changes(), 'No external change after save');
};

# ============================================================================
# Binary file detection
# ============================================================================
subtest 'Binary file detection' => sub {
    my $dir = tempdir(CLEANUP => 1);

    # Create a binary file with NUL bytes
    my $bin_path = "$dir/test.bin";
    open my $fh, '>:raw', $bin_path or die "Cannot create $bin_path: $!";
    print $fh "HEADER\x00\x01\x02binary data\x00";
    close $fh;

    my $doc = Zepto::Document->load($bin_path);
    ok($doc->{_is_binary}, 'Binary file detected');
    like($doc->text(), qr/Binary file/, 'Placeholder text shown for binary file');

    # Insert should be blocked on binary documents
    $doc->insert(0, 'x');
    like($doc->text(), qr/Binary file/, 'Insert blocked on binary document');

    # Delete should be blocked on binary documents
    $doc->delete(0, 1);
    like($doc->text(), qr/Binary file/, 'Delete blocked on binary document');

    # Save should be blocked on binary documents
    eval { $doc->save() };
    like($@, qr/Cannot save binary/, 'Save blocked on binary document');

    # Create a normal text file
    my $txt_path = "$dir/test.txt";
    open $fh, '>:encoding(UTF-8)', $txt_path or die;
    print $fh "Hello, world!\n";
    close $fh;

    my $txt_doc = Zepto::Document->load($txt_path);
    ok(!$txt_doc->{_is_binary}, 'Text file not detected as binary');
    is($txt_doc->text(), 'Hello, world!', 'Text content loaded normally');

    # Create a binary file with image extension
    my $img_path = "$dir/photo.png";
    open $fh, '>:raw', $img_path or die;
    print $fh "\x89PNG\r\n\x1a\n\x00\x00some image data";
    close $fh;

    my $img_doc = Zepto::Document->load($img_path);
    ok($img_doc->{_is_binary}, 'Image file detected as binary');
    ok($img_doc->{_is_image}, 'Image file flagged as image');
    like($img_doc->text(), qr/Image file/, 'Image placeholder text');

    # Non-image binary should not have _is_image flag
    ok(!$doc->{_is_image}, 'Non-image binary not flagged as image');
};

done_testing();
