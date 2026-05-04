#!/usr/bin/env bash
# QA-CMT-011: Blank line in selection is not commented
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-011: Blank line not commented"

file=$(qa_tmpfile_nl "cmt011.py" "x = 1

y = 2")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Toggle comment
qa_raw $'\x1f'

qa_assert_screen "# x = 1" "first line commented"
qa_assert_screen "# y = 2" "third line commented"

# Check blank line is still blank (not "# ")
qa_screen
blank_line_count=$(echo "$QA_SCREEN" | grep -c "^$" || true)
if [[ "$blank_line_count" -ge 1 ]] || ! echo "$QA_SCREEN" | grep -qE "^# $"; then
    qa_pass "blank line not commented"
else
    qa_fail "blank line got a comment prefix"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
