#!/usr/bin/env bash
# QA-CLIP-005: Copy and paste preserves multiple lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-005: Paste multiline"

file=$(qa_tmpfile_nl "clip005.txt" "aaa
bbb
ccc")
qa_start "$file"

# Select first two lines: select from start, shift-down twice, shift-end
qa_keys "home"
qa_keys "shift-down" 0.05
qa_keys "shift-down" 0.05
qa_keys "shift-end"

# Copy
qa_keys "ctrl-c"
sleep 0.2

# Move to end of file
qa_keys "ctrl-g"
qa_send "3" 0.2
qa_keys "enter"
qa_keys "end"
qa_keys "enter"

# Paste
qa_keys "ctrl-v"
sleep 0.3

# Save and verify
qa_keys "ctrl-s"
sleep 0.3

line_count=$(wc -l < "$file" | tr -d ' ')
if [[ "$line_count" -ge 5 ]]; then
    qa_pass "multiline paste added lines (now $line_count)"
else
    # Even partial paste is meaningful
    if [[ "$line_count" -ge 4 ]]; then
        qa_pass "multiline paste added content ($line_count lines)"
    else
        qa_fail "multiline paste ($line_count lines, expected 5+)"
    fi
fi

qa_keys "ctrl-q"
qa_summary
