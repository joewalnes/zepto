#!/usr/bin/env bash
# QA-REG-016: Find jumps to first match when off-screen
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-016: Find jumps to off-screen match"

# Create file with target at line 50
content=""
for i in $(seq 1 49); do content+="line $i nothing"$'\n'; done
content+="line 50 TARGETWORD"$'\n'
for i in $(seq 51 60); do content+="line $i more"$'\n'; done

file=$(qa_tmpfile "reg016.txt" "$content")
qa_start "$file"

# Open find and search
qa_keys "ctrl-f"
qa_send "TARGETWORD"
sleep 0.5

qa_assert_screen "TARGETWORD" "viewport scrolled to show match"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
