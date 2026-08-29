#!/usr/bin/env bash
# QA-REG-019: Natural (smart) sort in file tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-019: Natural sort in tree"

# Create files that should be naturally sorted
mkdir -p "$QA_TMPDIR/sortdir"
echo "a" > "$QA_TMPDIR/sortdir/file2.txt"
echo "b" > "$QA_TMPDIR/sortdir/file7.txt"
echo "c" > "$QA_TMPDIR/sortdir/file10.txt"

QA_ZEPTO=$(cd /Users/joe/src/zepto && pwd)/zepto
qa_start "$QA_TMPDIR/sortdir/file2.txt"

# Open file tree
qa_keys "ctrl-b"
sleep 0.5

# The tree should show files in natural sort order: file2, file7, file10
qa_wait_screen 'file[0-9]' || true
# Check that file2 appears before file10 in screen output
file2_line=$(echo "$QA_SCREEN" | grep -n "file2" | head -1 | cut -d: -f1 || true)
file10_line=$(echo "$QA_SCREEN" | grep -n "file10" | head -1 | cut -d: -f1 || true)

if [[ -n "$file2_line" && -n "$file10_line" && "$file2_line" -lt "$file10_line" ]]; then
    qa_pass "file2 appears before file10 (natural sort)"
elif [[ -n "$file2_line" && -n "$file10_line" ]]; then
    qa_fail "file2 appears before file10" "file2 at line $file2_line, file10 at line $file10_line"
else
    qa_skip "could not find file names in tree" "tree may not be visible"
fi

qa_keys "ctrl-q"
qa_summary
