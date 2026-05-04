#!/usr/bin/env bash
# QA-GOTO-011: New jump clears forward stack
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-011: New jump clears forward stack"

content=""
for i in $(seq 1 100); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "goto011.txt" "$content")
qa_start "$file"

# Jump to line 30
qa_keys "ctrl-g"
qa_send "30" 0.2
qa_keys "enter"
qa_assert_cursor_at "30" "at line 30"

# Jump to line 70
qa_keys "ctrl-g"
qa_send "70" 0.2
qa_keys "enter"
qa_assert_cursor_at "70" "at line 70"

# Go back to line 30
qa_keys "alt--"
qa_assert_cursor_at "30" "back to line 30"

# Make a NEW jump to line 50 (should clear forward)
qa_keys "ctrl-g"
qa_send "50" 0.2
qa_keys "enter"
qa_assert_cursor_at "50" "jumped to line 50"

# Try go forward -- should do nothing (forward stack cleared)
qa_keys "alt-="
qa_assert_cursor_at "50" "forward does nothing after new jump"

qa_keys "ctrl-q"
qa_summary
