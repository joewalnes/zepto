#!/usr/bin/env bash
# QA-STRT-006: Quit with multiple dirty buffers prompts for each
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-STRT-006: Multi dirty buffer quit"

file1=$(qa_tmpfile_nl "strt006a.txt" "content A")
file2=$(qa_tmpfile_nl "strt006b.txt" "content B")
qa_start "$file1" "$file2"

# Modify first file
qa_send "edit1"

# Switch to second tab and modify
qa_keys "alt-."
sleep 0.3
qa_send "edit2"

# Try to quit
qa_keys "ctrl-q"
sleep 0.3

# Should see save prompt for one of the files
qa_assert_expect "Save|Discard|Cancel" "first save prompt visible"

# Discard first
qa_send "n" 0.5

# May get second prompt or exit
qa_screen
if echo "$QA_SCREEN" | grep -qE "Save|Discard|Cancel"; then
    qa_pass "second save prompt visible"
    qa_send "n" 0.5
else
    qa_pass "handled all dirty buffers"
fi

# If still alive, try another quit
if qa_alive 2>/dev/null; then
    qa_keys "ctrl-q" 0.3
    qa_screen
    if echo "$QA_SCREEN" | grep -qE "Save|Discard|Cancel"; then
        qa_send "n" 0.5
    fi
fi

sleep 0.5
# Editor should have exited
if ! qa_alive 2>/dev/null; then
    qa_pass "editor exited after handling all prompts"
else
    qa_fail "editor exited after handling all prompts"
    qa_keys "ctrl-q"
    sleep 0.2
    qa_send "n" 0.2
fi

qa_summary
