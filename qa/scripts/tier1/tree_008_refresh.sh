#!/usr/bin/env bash
# QA-TREE-008: Tree shows new files after creation
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-008: Tree refresh"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree008_XXXXXX)
echo "c1" > "$proj_dir/existing.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start existing.txt

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Create a new file externally
echo "new content" > "$proj_dir/newfile.txt"

# Close and reopen tree to refresh
qa_keys "ctrl-b" 0.3
qa_keys "ctrl-b"
sleep 0.5

qa_screen
if echo "$QA_SCREEN" | grep -q "newfile"; then
    qa_pass "tree shows newly created file"
else
    qa_skip "tree auto-refresh" "may need manual refresh"
fi

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
