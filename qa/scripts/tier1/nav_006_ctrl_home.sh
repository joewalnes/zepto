#!/usr/bin/env bash
# QA-NAV-006+007: Ctrl+Home/End jumps to doc start/end
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-006: Ctrl+Home/End"

content=""
for i in $(seq 1 50); do
    content+="line $i"$'\n'
done
file=$(qa_tmpfile_nl "nav006.txt" "$content")
qa_start "$file"

# Go to end (Ctrl+End = CSI 1;5F)
qa_raw $'\x1b[1;5F'
qa_assert_screen "50" "at doc end, line 50 visible"

# Go to start (Ctrl+Home = CSI 1;5H)
qa_raw $'\x1b[1;5H'
qa_assert_screen "1:1" "ctrl+home returns to 1:1"

qa_keys "ctrl-q"
qa_summary
