#!/usr/bin/env bash
# QA-PREF-007: Tab width preference respected
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PREF-007: Tab width preference"

file=$(qa_tmpfile "pref007.py" "")
qa_start "$file"

# Default tab width is 4, type a tab
qa_keys "tab"
qa_send "x"

# Should see 4 spaces + x (cursor at col 6)
qa_assert_cursor_at "1:6" "tab inserted 4 spaces (cursor at col 6)"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
