#!/usr/bin/env bash
# QA-CLI-004: Open a directory shows file tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-004: Open directory shows file tree"

# Create temp dir with files
mkdir -p "$QA_TMPDIR/testdir"
echo "alpha content" > "$QA_TMPDIR/testdir/alpha.txt"
echo "beta content" > "$QA_TMPDIR/testdir/beta.txt"

qa_start "$QA_TMPDIR/testdir"

# Tree should be visible showing directory contents
qa_assert_expect "alpha" "alpha.txt visible in tree"
qa_assert_expect "beta" "beta.txt visible in tree"

qa_keys "ctrl-q"
qa_summary
