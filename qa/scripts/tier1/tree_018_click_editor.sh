#!/usr/bin/env bash
# QA-TREE-018: Click in editor area unfocuses tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-018: Click editor unfocuses tree"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree018_XXXXXX)
echo "editor content" > "$proj_dir/test.txt"
echo "other" > "$proj_dir/other.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start test.txt

# Open and focus tree
qa_keys "ctrl-b"
sleep 0.5

# Click in editor area
hangon mouse-click "$QA_SESSION" --x 50 --y 5
sleep 0.3

# Type should go to editor
qa_send "Z"
qa_assert_screen "Z" "typing goes to editor after click"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
