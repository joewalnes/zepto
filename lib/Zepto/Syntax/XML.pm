package Zepto::Syntax::XML;
# =============================================================================
# XML Syntax Grammar (inherits from HTML)
# =============================================================================
#
# XML and HTML share nearly identical syntax, so this inherits from HTML.
# The main differences (stricter closing tags, case sensitivity) don't
# affect tokenization.
#
# =============================================================================

use parent 'Zepto::Syntax::HTML';
use strict;
use warnings;

# All tokenization is handled by HTML.pm
# No additional code needed - inheritance does the work

1;
