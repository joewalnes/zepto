#!/usr/bin/env bash
# QA-FIF-006: Esc closes find-in-files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-006: Esc closes find-in-files"

proj_dir=$(mktemp -d /tmp/zepto_qa_fif006_XXXXXX)
echo "content" > "$proj_dir/test.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start test.txt

# Open find-in-files
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

qa_assert_expect "Find|Search|find" "find-in-files opened"

# Close with Esc
qa_keys "escape"
sleep 0.3

# Should be back to normal editor
qa_assert_expect "content" "back to editor after Esc"

qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
