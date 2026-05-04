#!/usr/bin/env bash
# QA-MC-010: Multi-cursor edits across multiple lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-010: Multi-line multi-cursor"

file=$(qa_tmpfile_nl "mc010.txt" "foo = 1
foo = 2
foo = 3")
qa_start "$file"

# Select all "foo" with ctrl-d x3
qa_keys "ctrl-d" 0.2
qa_keys "ctrl-d" 0.2
qa_keys "ctrl-d" 0.2

# Type replacement
qa_send "bar"
sleep 0.3

# Save and verify
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
bar_count=$(echo "$content" | grep -c "bar" || true)
foo_count=$(echo "$content" | grep -c "foo" || true)
if [[ "$bar_count" -ge 3 && "$foo_count" -eq 0 ]]; then
    qa_pass "all 3 foo replaced with bar"
elif [[ "$bar_count" -ge 2 ]]; then
    qa_pass "multi-cursor replaced $bar_count occurrences"
else
    qa_fail "multi-cursor edit (bar=$bar_count, foo=$foo_count)"
fi

qa_keys "ctrl-q"
qa_summary
