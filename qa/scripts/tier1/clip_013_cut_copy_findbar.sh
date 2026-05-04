#!/usr/bin/env bash
# QA-CLIP-013: Cut/copy/paste in find bar
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-013: Cut/copy/paste in find bar"

file=$(qa_tmpfile_nl "clip013.txt" "hello world")
qa_start "$file"

# Open find bar
qa_keys "ctrl-f"
qa_send "test query" 0.3

# Select all in find field
qa_keys "ctrl-a" 0.1

# Cut (ctrl-x)
qa_keys "ctrl-x"
sleep 0.3

# Paste back
qa_keys "ctrl-v"
sleep 0.3

qa_assert_screen "test query" "paste restored query in find bar"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
