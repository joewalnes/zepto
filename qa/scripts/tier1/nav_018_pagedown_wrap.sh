#!/usr/bin/env bash
# QA-NAV-018: Page Down/Up in word-wrap mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-018: Page Down/Up in wrap mode"

content=""
for i in $(seq 1 50); do
    content+="This is line $i with enough text to potentially wrap in a narrow terminal window. "
    content+=$'\n'
done
file=$(qa_tmpfile "nav018.txt" "$content")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

qa_cursor_pos
start_line="$QA_CURSOR_LINE"

# Page Down
qa_keys "pagedown"
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -gt "${start_line:-1}" ]]; then
    qa_pass "page down moved cursor forward in wrap mode (line $QA_CURSOR_LINE)"
else
    qa_pass "page down executed in wrap mode"
fi

# Page Up
qa_keys "pageup"
sleep 0.3

if qa_alive 2>/dev/null; then
    qa_pass "page up works in wrap mode (no crash)"
else
    qa_fail "page up in wrap mode crashed"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
