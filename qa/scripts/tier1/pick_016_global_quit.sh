#!/usr/bin/env bash
# QA-PICK-016: Global shortcuts work from picker
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-016: Global quit from picker"

file=$(qa_tmpfile_nl "pick016.txt" "content")
qa_start "$file"

# Open file picker
qa_keys "ctrl-p" 0.3

# Ctrl+Q should work even from picker
qa_keys "ctrl-q"
sleep 0.5

qa_assert_exited "ctrl-q works from picker"
