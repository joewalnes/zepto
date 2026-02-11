#!/usr/bin/env perl
# =============================================================================
# Bundled Build Syntax Check Test
# =============================================================================
#
# Tests that the bundled single-file zepto compiles without warnings.
# Full syntax highlighting functionality is tested in syntax_rendering.t
# using the development modules.
#
# =============================================================================

use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

# Ensure bundled zepto exists
my $zepto_path = "$RealBin/../zepto";

SKIP: {
    skip "zepto not built (run 'make build' first)", 1 unless -f $zepto_path;

    subtest 'Bundled zepto syntax check' => sub {
        my $output = `perl -c $zepto_path 2>&1`;
        like($output, qr/syntax OK/, 'Bundled zepto passes syntax check');
        unlike($output, qr/masks earlier declaration/, 'No variable masking warnings');
        unlike($output, qr/Can't locate/, 'No missing module errors');
    };
}

done_testing();
