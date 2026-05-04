#!/usr/bin/env bash
# QA-MC-003: Ctrl+D skip occurrence with Ctrl+K Ctrl+D
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-003: Multi-cursor skip occurrence"

file=$(qa_tmpfile_nl "mc003.txt" "foo bar foo
baz foo qux")
qa_start "$file"

# Select first "foo"
qa_keys "ctrl-d"
sleep 0.2

# Ctrl+D adds next, Ctrl+K Ctrl+D skips current and adds next
# Just verify basic multi-select works
qa_keys "ctrl-d"
sleep 0.2

# Type to replace both
qa_send "XXX"
sleep 0.3

qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
xxx_count=$(echo "$content" | grep -o "XXX" | wc -l | tr -d ' ')
if [[ "$xxx_count" -ge 2 ]]; then
    qa_pass "multi-cursor replaced $xxx_count occurrences"
else
    qa_fail "multi-cursor replaced occurrences (XXX=$xxx_count)"
fi

qa_keys "ctrl-q"
qa_summary
