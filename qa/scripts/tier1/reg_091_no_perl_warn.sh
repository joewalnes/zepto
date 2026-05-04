#!/usr/bin/env bash
# QA-REG-091: No Perl warnings on undo/redo near EOL (P0)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-091: No Perl warnings on undo near EOL (P0 regression)"

file=$(qa_tmpfile_nl "reg091.txt" "hello")
qa_start "$file"

# Move to end of line
qa_keys "end"

# Type a char then undo
qa_send "x"
qa_keys "ctrl-z"
sleep 0.3

# Type again and redo
qa_send "y"
qa_keys "ctrl-z"
qa_keys "ctrl-y"
sleep 0.3

# Editor should still be alive, no crash from Perl warning
if qa_alive; then
    qa_pass "no crash on undo/redo near EOL"
else
    qa_fail "no crash on undo/redo near EOL" "editor died"
fi

# Screen should show normal content
qa_assert_screen "hello" "content preserved"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
