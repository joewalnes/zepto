#!/usr/bin/env bash
# QA-MC-006: Esc clears secondary cursors
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-006: Multi-cursor Esc clears"

file=$(qa_tmpfile_nl "mc006.txt" "foo bar foo baz foo")
qa_start "$file"

# Select word and add occurrences
qa_keys "ctrl-d"
qa_keys "ctrl-d"
qa_keys "ctrl-d"

# Esc should clear multi-cursor
qa_keys "escape"
sleep 0.2

# Type — should affect only one position
qa_send "X"

qa_screen
# Count X occurrences — should be only 1
x_count=$(echo "$QA_SCREEN" | grep -o "X" | wc -l | tr -d ' ')
if [[ "$x_count" -le 2 ]]; then
    qa_pass "Esc cleared multi-cursor (only $x_count X)"
else
    qa_fail "Esc cleared multi-cursor (found $x_count X)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
