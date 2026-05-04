#!/usr/bin/env bash
# QA-REG-058: Ctrl+Q quits from palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-058: Quit from palette"

file=$(qa_tmpfile_nl "reg058.txt" "content")
qa_start "$file"

# Open palette
qa_keys "ctrl-space"
sleep 0.2

# Quit
qa_keys "ctrl-q"
sleep 0.5

qa_assert_exited "ctrl-q from palette exits"
