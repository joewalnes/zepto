#!/usr/bin/env bash
# QA-CLIP-002: Cut removes text and paste restores it
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-002: Cut and paste"

file=$(qa_tmpfile "clip002.txt" "hello world")
qa_start "$file"

# Select "world" (shift+end from after space)
qa_keys "end"
qa_keys "shift-home" 0.1

# Actually select "hello " — let's do it differently
# Select "hello" from start
qa_keys "home"
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1

# Cut
qa_keys "ctrl-x"
qa_assert_screen " world" "cut removed 'hello'"

# Move to end and paste
qa_keys "end"
qa_keys "ctrl-v"

qa_assert_screen "worldhello" "paste restored cut text"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
