#!/usr/bin/env bash
# QA-FIND-024: Find and Replace available in command palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-024: Find and Replace via palette"

file=$(qa_tmpfile_nl "find024.txt" "hello world test")
qa_start "$file"

# Open palette and search for replace
qa_keys "ctrl-space"
qa_send "find and replace"

qa_assert_expect "Find and Replace|Find & Replace|replace" "find and replace entry in palette"

# Execute it
qa_keys "enter"

# Replace field should be visible from the start
qa_assert_expect "Replace|replace" "replace field visible after palette command"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
