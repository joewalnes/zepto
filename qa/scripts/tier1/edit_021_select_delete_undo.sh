#!/usr/bin/env bash
# QA-EDIT-021: Select, delete, undo restores correctly
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-021: Select delete undo cycle"

file=$(qa_tmpfile_nl "edit021.txt" "hello world")
qa_start "$file"

# Select "hello" (5 chars)
for i in $(seq 1 5); do qa_keys "shift-right" 0.05; done

# Delete selection
qa_keys "delete"
sleep 0.2

# Should only have " world"
qa_assert_screen " world" "hello deleted"

# Undo
qa_keys "ctrl-z"
sleep 0.2

# Should be back to "hello world"
qa_assert_screen "hello world" "undo restored hello"

qa_keys "ctrl-q"
qa_summary
