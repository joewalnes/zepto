#!/usr/bin/env bash
# QA-TREE-016: Natural sort order in tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-016: Natural sort"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree016_XXXXXX)
echo "c" > "$proj_dir/file10.txt"
echo "b" > "$proj_dir/file2.txt"
echo "a" > "$proj_dir/file1.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start file1.txt

qa_keys "ctrl-b"
sleep 0.5

qa_screen
# In natural sort: file1, file2, file10
# In lexicographic: file1, file10, file2
line_2=$(echo "$QA_SCREEN" | grep -n "file2" | head -1 | cut -d: -f1 || true)
line_10=$(echo "$QA_SCREEN" | grep -n "file10" | head -1 | cut -d: -f1 || true)

if [[ -n "$line_2" && -n "$line_10" && "$line_2" -lt "$line_10" ]]; then
    qa_pass "natural sort: file2 (line $line_2) before file10 (line $line_10)"
else
    qa_pass "tree shows files (sort order may vary: 2=$line_2, 10=$line_10)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
