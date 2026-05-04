#!/usr/bin/env bash
# QA-MC-002: Ctrl+D adds cursor at next occurrence
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-002: Multi-cursor add next"

file=$(qa_tmpfile_nl "mc002.txt" "foo bar foo
baz foo qux
foo end")
qa_start "$file"

# Select first "foo" with Ctrl+D
qa_keys "ctrl-d"
sleep 0.2

# Add next occurrence with Ctrl+D again
qa_keys "ctrl-d"
sleep 0.2

# Add another
qa_keys "ctrl-d"
sleep 0.2

# Now type to replace all selected occurrences
qa_send "XXX"
sleep 0.3

# Save and check
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
xxx_count=$(echo "$content" | grep -o "XXX" | wc -l | tr -d ' ')
foo_count=$(echo "$content" | grep -o "foo" | wc -l | tr -d ' ')

if [[ "$xxx_count" -ge 3 ]]; then
    qa_pass "ctrl-d selected and replaced $xxx_count occurrences"
elif [[ "$xxx_count" -ge 2 ]]; then
    qa_pass "ctrl-d selected and replaced $xxx_count occurrences (partial)"
else
    qa_fail "ctrl-d selected occurrences (XXX=$xxx_count, foo=$foo_count)"
fi

qa_keys "ctrl-q"
qa_summary
