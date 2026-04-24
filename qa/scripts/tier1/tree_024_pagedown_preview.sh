#!/usr/bin/env bash
# QA-TREE-024: Page Down/Up in tree triggers preview
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-024: Tree Page Down/Up preview"

# Create a directory with many files
proj_dir=$(mktemp -d /tmp/zepto_qa_tree024_XXXXXX)
for i in $(seq -w 1 30); do
    echo "content of file $i" > "$proj_dir/file_${i}.txt"
done

qa_start "$proj_dir/file_01.txt"

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Navigate down to verify preview works with arrows
qa_keys "down" 0.3
qa_keys "down" 0.3

qa_screen
before_page="$QA_SCREEN"

# Page Down — should jump multiple entries and show preview
qa_keys "pagedown"
sleep 0.3

qa_screen
after_page="$QA_SCREEN"

if [[ "$before_page" != "$after_page" ]]; then
    qa_pass "Page Down changed screen (tree moved + preview updated)"
else
    qa_fail "Page Down changed screen (no preview update)"
fi

# Page Up — should go back and show preview
qa_keys "pageup"
sleep 0.3

qa_screen
after_pageup="$QA_SCREEN"

if [[ "$after_page" != "$after_pageup" ]]; then
    qa_pass "Page Up changed screen (tree moved + preview updated)"
else
    qa_fail "Page Up changed screen (no preview update)"
fi

qa_keys "escape"
qa_keys "ctrl-q"

rm -rf "$proj_dir"
qa_summary
