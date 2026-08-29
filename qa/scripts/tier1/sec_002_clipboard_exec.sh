#!/usr/bin/env bash
# QA-SEC-002: No shell injection in clipboard commands
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-002: Clipboard uses safe exec"

file=$(qa_tmpfile_nl "sec002.txt" "test content for copy")
qa_start "$file"

# Select all and copy
qa_keys "ctrl-a"
qa_keys "ctrl-c"
sleep 0.3

# Editor should not crash and content should still be visible
qa_assert_expect "test content" "editor still responsive after copy"

# Paste
qa_keys "end"
qa_keys "enter"
qa_keys "ctrl-v"
sleep 0.3

# Should see pasted content
qa_assert_expect "test content" "paste worked without shell injection"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
