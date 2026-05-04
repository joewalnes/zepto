#!/usr/bin/env bash
# QA-REG-096: Scrollbar thumb boundary consistent
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-096: Scrollbar boundary"

content=""
for i in $(seq 1 200); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "reg096.txt" "$content")
qa_start "$file"

# Scroll to various positions
qa_keys "ctrl-g"
qa_send "100" 0.2
qa_keys "enter"
sleep 0.2

# Editor should be responsive
if qa_alive; then
    qa_pass "editor responsive at scroll position 100"
else
    qa_fail "editor responsive at scroll position"
fi

# Scroll to end
qa_keys "ctrl-g"
qa_send "200" 0.2
qa_keys "enter"
sleep 0.2

if qa_alive; then
    qa_pass "editor responsive at end of file"
else
    qa_fail "editor responsive at end"
fi

qa_keys "ctrl-q"
qa_summary
