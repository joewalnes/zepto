#!/usr/bin/env perl
# Tests for Zepto::StateStore
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use lib 'lib';
use Zepto::StateStore;

# ============================================================================
# Construction
# ============================================================================
subtest 'Construction with custom base_dir' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);
    ok($store, 'StateStore created');
    is($store->base_dir(), $dir, 'base_dir set');
};

subtest 'Default base_dir uses XDG_CONFIG_HOME' => sub {
    local $ENV{XDG_CONFIG_HOME} = '/tmp/test-xdg';
    my $store = Zepto::StateStore->new();
    is($store->base_dir(), '/tmp/test-xdg/zepto', 'Uses XDG_CONFIG_HOME');
};

subtest 'Default base_dir falls back to HOME/.config' => sub {
    local $ENV{XDG_CONFIG_HOME} = undef;
    local $ENV{HOME} = '/tmp/test-home';
    my $store = Zepto::StateStore->new();
    is($store->base_dir(), '/tmp/test-home/.config/zepto', 'Falls back to HOME/.config');
};

# ============================================================================
# Basic get/put
# ============================================================================
subtest 'Get returns empty hash for missing category' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);
    my $data = $store->get('preferences');
    is_deeply($data, {}, 'Empty hash for missing file');
};

subtest 'Put and get roundtrip' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);
    $store->put('preferences', { theme => 'dark', tab_width => 4 });
    my $data = $store->get('preferences');
    is($data->{theme}, 'dark', 'theme roundtripped');
    is($data->{tab_width}, 4, 'tab_width roundtripped');
};

subtest 'Put creates directory if missing' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $nested = "$dir/sub/zepto";
    my $store = Zepto::StateStore->new(base_dir => $nested);
    $store->put('preferences', { theme => 'light' });
    ok(-d $nested, 'Directory created');
    ok(-f "$nested/preferences.json", 'File created');
};

# ============================================================================
# Merge semantics
# ============================================================================
subtest 'Put merges with existing data' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('preferences', { theme => 'dark', tab_width => 4 });
    $store->put('preferences', { word_wrap => 1 });

    my $data = $store->get('preferences');
    is($data->{theme}, 'dark', 'Existing key preserved');
    is($data->{tab_width}, 4, 'Existing key preserved');
    is($data->{word_wrap}, 1, 'New key added');
};

subtest 'Put overwrites conflicting keys' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('preferences', { theme => 'dark' });
    $store->put('preferences', { theme => 'light' });

    my $data = $store->get('preferences');
    is($data->{theme}, 'light', 'Caller key wins');
};

subtest 'Cross-instance merge' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store_a = Zepto::StateStore->new(base_dir => $dir);
    my $store_b = Zepto::StateStore->new(base_dir => $dir);

    $store_a->put('preferences', { theme => 'dark' });
    sleep 1;  # Ensure mtime differs so store_b's put reads fresh data
    $store_b->put('preferences', { word_wrap => 1 });

    # store_b's put merges with on-disk, so both keys should exist on disk.
    # Read via a fresh store to bypass caching.
    my $store_c = Zepto::StateStore->new(base_dir => $dir);
    my $data = $store_c->get('preferences');
    is($data->{theme}, 'dark', 'Key from A preserved');
    is($data->{word_wrap}, 1, 'Key from B merged');
};

# ============================================================================
# Array values (e.g. recent_files)
# ============================================================================
subtest 'Array values roundtrip' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    my @files = ('/tmp/a.txt', '/tmp/b.txt', '/tmp/c.txt');
    $store->put('history', { recent_files => \@files });

    my $data = $store->get('history');
    is_deeply($data->{recent_files}, \@files, 'Array roundtripped');
};

# ============================================================================
# Corrupt/invalid file handling
# ============================================================================
subtest 'Corrupt JSON returns empty hash' => sub {
    my $dir = tempdir(CLEANUP => 1);
    mkdir $dir unless -d $dir;

    # Write garbage to the file
    open my $fh, '>', "$dir/preferences.json";
    print $fh "not json {{{";
    close $fh;

    my $store = Zepto::StateStore->new(base_dir => $dir);
    my $data = $store->get('preferences');
    is_deeply($data, {}, 'Corrupt file returns empty hash');
};

subtest 'Non-hash JSON returns empty hash' => sub {
    my $dir = tempdir(CLEANUP => 1);
    mkdir $dir unless -d $dir;

    open my $fh, '>', "$dir/preferences.json";
    print $fh '["an","array"]';
    close $fh;

    my $store = Zepto::StateStore->new(base_dir => $dir);
    my $data = $store->get('preferences');
    is_deeply($data, {}, 'Non-hash JSON returns empty hash');
};

# ============================================================================
# Caching
# ============================================================================
subtest 'Get uses cache on second call' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('preferences', { theme => 'dark' });
    my $data1 = $store->get('preferences');
    my $data2 = $store->get('preferences');

    # Same reference means cache was used
    is($data1, $data2, 'Same hashref returned (cached)');
};

subtest 'Cache invalidated on external change' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('preferences', { theme => 'dark' });
    my $data1 = $store->get('preferences');

    # Simulate external write with different mtime
    sleep 1;  # Ensure mtime differs
    open my $fh, '>', "$dir/preferences.json";
    print $fh '{"theme":"light"}';
    close $fh;

    my $data2 = $store->get('preferences');
    is($data2->{theme}, 'light', 'Cache invalidated on mtime change');
};

# ============================================================================
# Secrets permissions
# ============================================================================
subtest 'Secrets file gets mode 0600' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('secrets', { api_key => 'sk-test-123' });

    my $mode = (stat("$dir/secrets.json"))[2] & 07777;
    is(sprintf('%04o', $mode), '0600', 'Secrets file is mode 0600');
};

# ============================================================================
# Category validation
# ============================================================================
subtest 'Invalid category names rejected' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    eval { $store->get('../etc/passwd') };
    like($@, qr/Invalid category/, 'Path traversal rejected');

    eval { $store->get('has spaces') };
    like($@, qr/Invalid category/, 'Spaces rejected');

    eval { $store->get('has/slash') };
    like($@, qr/Invalid category/, 'Slashes rejected');

    eval { $store->put('UPPER', {}) };
    like($@, qr/Invalid category/, 'Uppercase rejected');
};

# ============================================================================
# Change detection and callbacks
# ============================================================================
subtest 'check_for_changes fires callback on external modification' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    # Prime the cache
    $store->put('preferences', { theme => 'dark' });
    $store->get('preferences');

    # Register listener
    my $called_with;
    $store->on_change('preferences', sub { $called_with = $_[0] });

    # Simulate external write
    sleep 1;  # Ensure mtime differs
    open my $fh, '>', "$dir/preferences.json";
    print $fh '{"theme":"light","word_wrap":1}';
    close $fh;

    my $changed_count = $store->check_for_changes();
    ok(defined $called_with, 'Callback fired');
    is($called_with->{theme}, 'light', 'Callback received new data');
    is($called_with->{word_wrap}, 1, 'Callback received all new data');
    is($changed_count, 1, 'check_for_changes returns the number of changed categories (used by Editor::run to decide whether to re-render an idle instance)');
};

subtest 'check_for_changes does not fire for own writes' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('preferences', { theme => 'dark' });

    my $called = 0;
    $store->on_change('preferences', sub { $called = 1 });

    # Our own write should not trigger
    $store->put('preferences', { theme => 'light' });
    $store->check_for_changes();
    is($called, 0, 'Own writes do not fire callback');
};

subtest 'check_for_changes skips unchanged files' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('preferences', { theme => 'dark' });
    $store->get('preferences');

    my $called = 0;
    $store->on_change('preferences', sub { $called = 1 });

    # No external change
    my $changed_count = $store->check_for_changes();
    is($called, 0, 'No callback when unchanged');
    is($changed_count, 0, 'check_for_changes returns 0 when nothing changed');
};

# ============================================================================
# Atomic write safety
# ============================================================================
subtest 'File contains valid JSON after put' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('preferences', { theme => 'dark', tab_width => 4 });

    # Read raw file and verify it's valid JSON
    open my $fh, '<', "$dir/preferences.json";
    local $/;
    my $content = <$fh>;
    close $fh;

    my $data = eval { JSON::PP->new->decode($content) };
    ok(!$@, 'File contains valid JSON');
    is($data->{theme}, 'dark', 'Correct data in file');
};

subtest 'No temp files left behind' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $store = Zepto::StateStore->new(base_dir => $dir);

    $store->put('preferences', { theme => 'dark' });

    opendir(my $dh, $dir);
    my @tmp = grep { /\.tmp\./ } readdir($dh);
    closedir($dh);

    is(scalar @tmp, 0, 'No temp files remain');
};

done_testing();
