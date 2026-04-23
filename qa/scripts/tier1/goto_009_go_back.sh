#!/usr/bin/env bash
# QA-GOTO-009+010: Go Back (Alt+-) and Go Forward (Alt+=)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-009: Go Back/Forward"

content=""
for i in $(seq 1 100); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "goto009.txt" "$content")
qa_start "$file"

# Jump to line 50
qa_keys "ctrl-g"
qa_send "50" 0.2
qa_keys "enter"
qa_assert_screen "50" "at line 50"

# Jump to line 80
qa_keys "ctrl-g"
qa_send "80" 0.2
qa_keys "enter"
qa_assert_screen "80" "at line 80"

# Go Back (Alt+-)
qa_keys "alt--"
qa_assert_screen "50" "go back returns to line 50"

# Go Forward (Alt+=)
qa_keys "alt-="
qa_assert_screen "80" "go forward returns to line 80"

qa_keys "ctrl-q"
qa_summary
