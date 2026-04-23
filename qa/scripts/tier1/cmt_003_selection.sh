#!/usr/bin/env bash
# QA-CMT-003: Toggle comment on multi-line selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-003: Comment selection"

file=$(qa_tmpfile_nl "cmt003.py" "x = 1
y = 2
z = 3")
qa_start "$file"

# Select all lines
qa_keys "ctrl-a"

# Toggle comment
qa_raw $'\x1f'

qa_assert_screen "# x = 1" "line 1 commented"
qa_assert_screen "# y = 2" "line 2 commented"
qa_assert_screen "# z = 3" "line 3 commented"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
