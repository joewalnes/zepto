#!/usr/bin/env perl
# Tests for Zepto::Config
use strict;
use warnings;
use Test::More;
use lib 'lib';
use Zepto::Config;

# =============================================================================
# Skip directories
# =============================================================================
subtest 'skip_directories returns list' => sub {
    my @dirs = Zepto::Config::skip_directories();
    ok(scalar @dirs > 0, 'skip_directories returns non-empty list');

    # Must include common VCS and build directories
    my %dirs = map { $_ => 1 } @dirs;
    ok($dirs{'.git'}, '.git is skipped');
    ok($dirs{'node_modules'}, 'node_modules is skipped');
    ok($dirs{'__pycache__'}, '__pycache__ is skipped');
};

subtest 'skip_directories_hash returns hash' => sub {
    my %hash = Zepto::Config::skip_directories_hash();
    ok(scalar keys %hash > 0, 'skip_directories_hash returns non-empty hash');
    is($hash{'.git'}, 1, '.git maps to 1');
    is($hash{'node_modules'}, 1, 'node_modules maps to 1');
    ok(!exists $hash{'src'}, 'src is not in skip list');
};

# =============================================================================
# Limit accessors
# =============================================================================
subtest 'max_files returns positive integer' => sub {
    my $val = Zepto::Config::max_files();
    ok(defined $val, 'max_files is defined');
    ok($val > 0, 'max_files is positive');
    is($val, 10_000, 'max_files default is 10000');
};

subtest 'max_depth returns positive integer' => sub {
    my $val = Zepto::Config::max_depth();
    ok(defined $val, 'max_depth is defined');
    ok($val > 0, 'max_depth is positive');
    is($val, 15, 'max_depth default is 15');
};

subtest 'picker_visible_rows returns positive integer' => sub {
    my $val = Zepto::Config::picker_visible_rows();
    ok(defined $val, 'picker_visible_rows is defined');
    ok($val > 0, 'picker_visible_rows is positive');
    is($val, 10, 'picker_visible_rows default is 10');
};

done_testing();
