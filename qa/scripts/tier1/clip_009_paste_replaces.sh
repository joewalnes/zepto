#!/usr/bin/env bash
# QA-CLIP-009: Paste replaces selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-009: Paste replaces selection"

file=$(qa_tmpfile "clip009.txt" "hello world")
qa_start "$file"

# Select and copy "hello"
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "ctrl-c"

# Select "world"
qa_keys "end"
qa_keys "shift-left" 0.1
qa_keys "shift-left" 0.1
qa_keys "shift-left" 0.1
qa_keys "shift-left" 0.1
qa_keys "shift-left" 0.1

# Paste — should replace "world" with "hello".
# Expect-based wait: a fixed post-keys sleep flaked under full-suite load.
qa_keys "ctrl-v" 0.1
qa_assert_expect "hello hello" "paste replaced selection"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
