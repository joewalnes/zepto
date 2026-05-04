#!/usr/bin/env bash
# QA-REG-093: Clean exit with no screen artifacts
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-093: Clean exit no artifacts"

file=$(qa_tmpfile_nl "reg093.txt" "test content")
qa_start "$file"

qa_assert_screen "test content" "editor running"

# Quit
qa_keys "ctrl-q"
sleep 0.5

# Editor should have exited
qa_assert_exited "editor exited cleanly"

qa_summary
