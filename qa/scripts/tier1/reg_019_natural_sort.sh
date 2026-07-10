#!/usr/bin/env bash
# QA-REG-019: Natural (smart) sort in file tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-019: Natural sort in tree"

# Create files that should be naturally sorted
proj_dir=$(mktemp -d /tmp/zepto_qa_reg019_XXXXXX)
echo "a" > "$proj_dir/file2.txt"
echo "b" > "$proj_dir/file7.txt"
echo "c" > "$proj_dir/file10.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir" || exit 1
qa_start file2.txt

# Open file tree
qa_keys "ctrl-b"
sleep 0.5

# The tree should show files in natural sort order: file2, file7, file10
qa_screen
# Check that file2 appears before file10 in screen output
file2_line=$(echo "$QA_SCREEN" | grep -n "file2" | head -1 | cut -d: -f1 || true)
file10_line=$(echo "$QA_SCREEN" | grep -n "file10" | head -1 | cut -d: -f1 || true)

if [[ -n "$file2_line" && -n "$file10_line" && "$file2_line" -lt "$file10_line" ]]; then
    qa_pass "file2 appears before file10 (natural sort)"
elif [[ -n "$file2_line" && -n "$file10_line" ]]; then
    qa_fail "file2 appears before file10" "file2 at line $file2_line, file10 at line $file10_line"
else
    qa_fail "could not find file names in tree" "tree may not be visible"
fi

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
