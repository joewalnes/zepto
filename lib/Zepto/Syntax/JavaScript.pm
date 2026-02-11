package Zepto::Syntax::JavaScript;
# =============================================================================
# JavaScript Syntax Grammar (inherits from TypeScript)
# =============================================================================
#
# Since TypeScript is a superset of JavaScript, the TypeScript grammar handles
# both languages. This module exists for semantic clarity and proper detection.
#
# =============================================================================

use parent 'Zepto::Syntax::TypeScript';
use strict;
use warnings;

# All tokenization is handled by TypeScript.pm
# No additional code needed - inheritance does the work

1;
