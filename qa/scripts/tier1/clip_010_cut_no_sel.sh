#!/usr/bin/env bash
# QA-CLIP-010: Cut with no selection cuts current line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-010: Cut line (no selection)"

file=$(qa_tmpfile_nl "clip010.txt" "line one
line two
line three")
qa_start "$file"

# Move to line 2 with no selection
qa_keys "down"

# Cut (Ctrl+X with no selection should cut the whole line)
qa_keys "ctrl-x"

qa_assert_not_screen "line two" "line two was cut"
qa_assert_screen "line one" "line one still present"
qa_assert_screen "line three" "line three still present"

# Paste it back to verify it was copied
qa_keys "ctrl-v"
qa_assert_expect "line two" "cut line pasted back"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
