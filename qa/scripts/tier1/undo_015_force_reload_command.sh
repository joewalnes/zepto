#!/usr/bin/env bash
# QA-UNDO-015: Undo stack behavior after command-palette forced reload
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-015: Undo after command-palette forced reload"

file=$(qa_tmpfile_nl "undo015.txt" "original content")
qa_start "$file"

# Modify
qa_keys "end"
qa_send " modified"
sleep 0.2

# Force reload from disk (close and reopen same file)
qa_keys "ctrl-space"
qa_send "reload" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qiE "reload|Reload"; then
    qa_keys "enter" 0.3
fi
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# After reload, undo should either be cleared or work gracefully
qa_keys "ctrl-z"
sleep 0.2

if qa_alive; then
    qa_pass "undo after reload handled gracefully"
else
    qa_fail "undo after reload crashed"
fi

qa_keys "ctrl-q"
qa_summary
