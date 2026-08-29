#!/usr/bin/env bash
# QA-HELP-004: License doc accessible from palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-HELP-004: License in palette"

file=$(qa_tmpfile_nl "help004.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "license" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qiE "license|License"; then
    qa_pass "license command found in palette"
    qa_keys "enter"
    sleep 0.5
    qa_assert_expect "MIT|License|license|Copyright|copyright" "license content displayed"
    qa_keys "ctrl-w"
else
    qa_fail "license command found in palette"
    qa_keys "escape"
    qa_keys "escape"
fi

qa_keys "ctrl-q"
qa_summary
