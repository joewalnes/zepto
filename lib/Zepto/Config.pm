package Zepto::Config;
# =============================================================================
# Configuration for Zepto Editor
# =============================================================================
#
# This file contains easily-editable configuration values.
# Edit these to customize zepto's behavior.
#
# =============================================================================

use strict;
use warnings;

# =============================================================================
# File Picker - Directories to Skip
# =============================================================================
#
# These directories are excluded from the file picker (Ctrl+O).
# They typically contain generated, vendored, or internal files
# that you don't want cluttering your search results.
#

our @SKIP_DIRECTORIES = qw(
    .git
    .svn
    .hg
    .jj
    node_modules
    vendor
    __pycache__
    .pytest_cache
    target
    build
    dist
    out
    .idea
    .vscode
    .cache
    .npm
    .yarn
);

# =============================================================================
# File Picker - Limits
# =============================================================================

# Maximum number of files to index (prevents memory issues in huge repos)
our $MAX_FILES = 10_000;

# Maximum directory depth to traverse
our $MAX_DEPTH = 15;

# Number of results visible in file picker
our $PICKER_VISIBLE_ROWS = 10;

# =============================================================================
# Accessors
# =============================================================================

sub skip_directories {
    return @SKIP_DIRECTORIES;
}

sub skip_directories_hash {
    return map { $_ => 1 } @SKIP_DIRECTORIES;
}

sub max_files { $MAX_FILES }
sub max_depth { $MAX_DEPTH }
sub picker_visible_rows { $PICKER_VISIBLE_ROWS }

1;
