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

# Real assertion: "hello" was copied and appended after "world", so the only
# way "worldhello" appears on screen is if paste actually inserted the
# clipboard contents at the new cursor location. Merely having typed
# "hello world" earlier does NOT produce this substring on its own, unlike
# a bare `grep -q "hello"` check (which would pass even with paste broken).
qa_assert_screen "worldhello" "paste inserted copied text after original content"

# Belt-and-braces: "hello" must now appear twice (once in the original
# text, once from the pasted duplicate).
qa_screen
hello_count=$(echo "$QA_SCREEN" | grep -o "hello" | wc -l | tr -d ' ')
if [[ "$hello_count" -ge 2 ]]; then
    qa_pass "clipboard content duplicated on screen ($hello_count occurrences of 'hello')"
else
    qa_fail "clipboard content duplicated on screen" "expected >=2 occurrences of 'hello', got $hello_count"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2

qa_summary
