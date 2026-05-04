#!/usr/bin/env bash
# QA-LINE-005: Alt+Up with selection moves all selected lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-005: Move selected lines up"

file=$(qa_tmpfile_nl "line005.txt" "first
second
third
fourth
fifth")
qa_start "$file"

# Select lines 3-4 (third, fourth)
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "shift-down" 0.1
qa_keys "shift-down" 0.1

# Move selection up
qa_keys "alt-up"
sleep 0.3

# Save and verify
qa_keys "ctrl-s"
sleep 0.3

# After moving lines 3-4 up: first, third, fourth, second, fifth
qa_assert_file_contains "$file" "first" "first line still first"

content=$(cat "$file")
# Check that third appears before second
third_pos=$(echo "$content" | grep -n "third" | head -1 | cut -d: -f1)
second_pos=$(echo "$content" | grep -n "second" | head -1 | cut -d: -f1)

if [[ -n "$third_pos" && -n "$second_pos" && "$third_pos" -lt "$second_pos" ]]; then
    qa_pass "selected lines moved up (third at line $third_pos, second at line $second_pos)"
else
    qa_fail "selected lines moved up" "third=$third_pos, second=$second_pos"
fi

qa_keys "ctrl-q"
qa_summary
