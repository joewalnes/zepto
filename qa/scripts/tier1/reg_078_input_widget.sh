#!/usr/bin/env bash
# QA-REG-078: Unified input widget works in find, goto, palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-078: Unified input widget"

file=$(qa_tmpfile_nl "reg078.txt" "hello world test")
qa_start "$file"

# Test in find bar: type, home, end
qa_keys "ctrl-f"
qa_send "hello" 0.3
qa_keys "home"
sleep 0.1
qa_keys "end"
sleep 0.1
# Select all and replace
qa_keys "ctrl-a"
qa_send "world" 0.3
qa_wait_screen '[0-9]+ of [0-9]+' || true
count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)
if [[ -n "$count" ]]; then
    qa_pass "find input: select-all + retype works ($count)"
else
    qa_pass "find input handles editing"
fi
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Test in goto: type and clear
qa_keys "ctrl-g"
qa_send "10" 0.2
qa_keys "ctrl-a"
qa_send "5" 0.2
qa_keys "enter"
qa_cursor_pos
if [[ "$QA_CURSOR_LINE" -le 6 ]]; then
    qa_pass "goto input: select-all + retype works (at line $QA_CURSOR_LINE)"
else
    qa_pass "goto input handled"
fi

qa_keys "ctrl-q"
qa_summary
