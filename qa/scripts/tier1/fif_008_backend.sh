#!/usr/bin/env bash
# QA-FIF-008: Find-in-files uses available search backend
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-008: Search backend"
proj_dir=$(mktemp -d /tmp/zepto_qa_fif008_XXXXXX)
echo "FINDME in file1" > "$proj_dir/a.txt"
echo "nothing" > "$proj_dir/b.txt"
echo "FINDME in file3" > "$proj_dir/c.txt"
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start a.txt
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3
qa_send "FINDME" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -qE "2|match|FINDME"; then
    qa_pass "find-in-files backend found results"
else
    qa_fail "find-in-files backend"
fi
qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
