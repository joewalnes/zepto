#!/usr/bin/env bash
# QA-FIND-009: Regex toggle in find bar (Ctrl+R)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-009: Regex toggle"

file=$(qa_tmpfile_nl "find009.txt" "foo123
bar456
baz789
foo000")
qa_start "$file"

# Open find, type a regex pattern
qa_keys "ctrl-f"
qa_send 'foo|bar' 0.3

qa_screen
first_count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)

# Toggle regex with Ctrl+R
qa_keys "ctrl-r" 0.3

qa_screen
toggled_count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)

# One state should match 3 (regex: foo OR bar), the other 0 (literal "foo|bar")
if [[ -n "$first_count" && -n "$toggled_count" && "$first_count" != "$toggled_count" ]]; then
    qa_pass "regex toggle changed results ($first_count → $toggled_count)"
elif [[ -z "$first_count" && -n "$toggled_count" ]]; then
    qa_pass "regex toggle enabled matches (none → $toggled_count)"
elif [[ -n "$first_count" && -z "$toggled_count" ]]; then
    qa_pass "regex toggle disabled matches ($first_count → none)"
else
    qa_fail "regex toggle changed results (before=${first_count:-none} after=${toggled_count:-none})"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
