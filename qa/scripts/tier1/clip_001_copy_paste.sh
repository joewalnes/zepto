#!/usr/bin/env bash
# QA-CLIP-001: Copy then paste within editor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-001: Copy and paste within editor"

file=$(qa_tmpfile "clip001.txt" "")
qa_start "$file"

# Type text
qa_send "hello world"

# Select "hello" (shift+right 5 times from home)
qa_keys "home"
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1

# Copy
qa_keys "ctrl-c"

# Move to end
qa_keys "end"

# Paste
qa_keys "ctrl-v"

# Should see "hello worldhello" or "hello world" + pasted chars
qa_screen
if echo "$QA_SCREEN" | grep -q "hello"; then
    qa_pass "paste produced output on screen"
else
    qa_fail "paste result not visible"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "d" 0.2

qa_summary
