#!/usr/bin/env perl
# Test harness validation - ensures our test infrastructure works
use strict;
use warnings;
use Test::More;

# Verify Test::More is working
ok(1, 'Test::More is functional');
is(1 + 1, 2, 'Basic arithmetic works');
isnt(1, 2, 'isnt works');
like('hello', qr/ell/, 'like works');
unlike('hello', qr/xyz/, 'unlike works');

# Test data structure comparisons
is_deeply([1, 2, 3], [1, 2, 3], 'is_deeply works for arrays');
is_deeply({a => 1}, {a => 1}, 'is_deeply works for hashes');

done_testing();
