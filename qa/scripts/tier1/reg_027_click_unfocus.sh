#!/usr/bin/env bash
# QA-REG-027: Click in editor unfocuses tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-027: Click editor unfocuses tree"

proj_dir=$(mktemp -d /tmp/zepto_qa_reg027_XXXXXX)
echo "content" > "$proj_dir/test.txt"
echo "other" > "$proj_dir/other.txt"
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start test.txt

# Open and focus tree
qa_keys "ctrl-b"
sleep 0.5

# Click in editor area (right side)
hangon mouse-click "$QA_SESSION" --x 50 --y 5
sleep 0.3

# Should be able to type (editor focused, not tree)
qa_send "X"
qa_assert_screen "X" "typing works after click — editor focused"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
