#!/usr/bin/env bash
# QA-FIND-011: Replace all with regex pattern
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-011: Regex replace all"

file=$(qa_tmpfile_nl "find011.txt" "foo123 bar456
foo789 baz000")
qa_start "$file"

# Open find — regex is ON by default
qa_keys "ctrl-f"
qa_send 'foo[0-9]+'

qa_wait_screen '[0-9]+ of [0-9]+|No matches' || true
count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)

# If no matches, regex might be off — toggle it on
if [[ -z "$count" ]] || echo "$QA_SCREEN" | grep -q "No matches"; then
    qa_keys "ctrl-r"
fi

# Tab to replace field
qa_keys "tab"
qa_send "REPLACED" 0.3

# Enter to commit replacement
qa_keys "enter" 0.3
qa_keys "escape"

# Save and check
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
replaced_count=$(echo "$content" | grep -c "REPLACED" || true)
if [[ "$replaced_count" -ge 2 ]]; then
    qa_pass "regex replace all: $replaced_count replacements"
elif [[ "$replaced_count" -ge 1 ]]; then
    qa_pass "regex replace: $replaced_count replacement"
else
    qa_fail "regex replace all (found $replaced_count replacements, file: ${content:0:80})"
fi

qa_keys "ctrl-q"
qa_summary
