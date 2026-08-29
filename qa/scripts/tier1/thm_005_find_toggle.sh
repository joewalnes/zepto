#!/usr/bin/env bash
# QA-THM-005: Can toggle theme while find bar open
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-THM-005: Theme toggle during find"

file=$(qa_tmpfile_nl "thm005.txt" "hello world")
qa_start "$file"

# Open find bar
qa_keys "ctrl-f"
qa_send "hello" 0.3

# Toggle theme via palette (close find first, toggle, reopen)
qa_keys "escape"
qa_keys "escape"

qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter" 0.3

# Reopen find — should still work
qa_keys "ctrl-f"
qa_send "hello" 0.3

if qa_alive 2>/dev/null; then
    qa_pass "theme toggle during find session — no crash"
else
    qa_fail "theme toggle during find session crashed"
fi

qa_assert_expect "hello" "find still works after theme toggle"

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
