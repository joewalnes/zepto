#!/usr/bin/env bash
# QA-STRT-003: Clean quit with no unsaved changes
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-STRT-003: Clean quit exits immediately"

file=$(qa_tmpfile_nl "strt003.txt" "hello world")
qa_start "$file"

# Verify editor is alive
qa_assert_expect "hello world" "editor showing content"

# Quit without making changes
qa_keys "ctrl-q"
sleep 0.5

# Session should have exited
qa_assert_exited "editor exited cleanly after Ctrl+Q"

qa_summary
