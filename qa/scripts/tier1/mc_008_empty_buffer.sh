#!/usr/bin/env bash
# QA-MC-008: Ctrl+D on empty buffer does not crash
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-008: Ctrl+D on empty buffer"

file=$(qa_tmpfile "mc008.txt" "")
qa_start "$file"

# Try Ctrl+D on empty buffer
qa_keys "ctrl-d"
sleep 0.3
qa_keys "ctrl-d"
sleep 0.3

# Editor should still be alive
if qa_alive; then
    qa_pass "editor alive after Ctrl+D on empty buffer"
else
    qa_fail "editor alive after Ctrl+D on empty buffer"
fi

# Should still be responsive
qa_send "hello"
qa_assert_screen "hello" "can still type after Ctrl+D on empty"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
