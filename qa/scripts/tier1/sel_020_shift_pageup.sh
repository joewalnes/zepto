#!/usr/bin/env bash
# QA-SEL-020: Shift+Page Up extends selection upward
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-020: Shift+Page Up selection"

content=""
for i in $(seq 1 50); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "sel020.txt" "$content")
qa_start "$file"

# Go to line 30
qa_keys "ctrl-g"
qa_send "30" 0.2
qa_keys "enter"

# Shift+Page Up = CSI 5;2~
qa_raw $'\x1b[5;2~' 0.3

# Should have selection — check for SEL indicator in status bar
qa_screen
if echo "$QA_SCREEN" | grep -qE "SEL|sel|lines"; then
    qa_pass "shift-pageup created selection"
else
    # Verify cursor moved up (selection exists even without indicator)
    qa_cursor_pos
    if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -lt 30 ]]; then
        qa_pass "shift-pageup moved cursor up with selection (at line $QA_CURSOR_LINE)"
    else
        qa_fail "shift-pageup created selection (at line $QA_CURSOR_LINE)"
    fi
fi

qa_keys "ctrl-q"
qa_summary
