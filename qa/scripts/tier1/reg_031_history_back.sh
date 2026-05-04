#!/usr/bin/env bash
# QA-REG-031: Location history back/forward (Alt+- / Alt+=)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-031: Location history back/forward"

content=""
for i in $(seq 1 100); do content+="line $i content"$'\n'; done
file=$(qa_tmpfile_nl "reg031.txt" "$content")
qa_start "$file"

# Jump to line 40
qa_keys "ctrl-g"
qa_send "40" 0.2
qa_keys "enter"
qa_assert_cursor_at "40" "jumped to line 40"

# Jump to line 80
qa_keys "ctrl-g"
qa_send "80" 0.2
qa_keys "enter"
qa_assert_cursor_at "80" "jumped to line 80"

# Go back
qa_keys "alt--"
qa_assert_cursor_at "40" "Alt+- returned to line 40"

# Go forward
qa_keys "alt-="
qa_assert_cursor_at "80" "Alt+= returned to line 80"

qa_keys "ctrl-q"
qa_summary
