#!/usr/bin/env bash
# QA-TREE-024: Page Down/Up in tree triggers preview
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-024: Tree Page Down/Up preview"

# Create a directory with uniquely identifiable files
proj_dir=$(mktemp -d /tmp/zepto_qa_tree024_XXXXXX)
for i in $(seq -w 1 30); do
    echo "CONTENT_$i" > "$proj_dir/file_${i}.txt"
done

# Must cd so the tree shows these files (tree uses CWD)
# Resolve QA_ZEPTO to absolute path before cd
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start file_01.txt

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Arrow down — preview should update to file_02
qa_keys "down"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "CONTENT_02"; then
    qa_pass "arrow down preview shows file_02"
else
    qa_fail "arrow down preview shows file_02"
fi

# Page Down — preview must update to the newly highlighted file
qa_keys "pagedown"
sleep 0.3

qa_screen
# After page down from file_02, we should NOT still see CONTENT_02
# The preview should show a different file's content
if echo "$QA_SCREEN" | grep -q "CONTENT_02"; then
    qa_fail "page down preview still shows file_02 (stale preview)"
else
    # Check that SOME content is showing (not blank)
    if echo "$QA_SCREEN" | grep -q "CONTENT_"; then
        qa_pass "page down preview updated to new file"
    else
        qa_fail "page down preview shows no content"
    fi
fi

qa_keys "escape"
qa_keys "ctrl-q"

cd /Users/joe/src/zepto
rm -rf "$proj_dir"
qa_summary
