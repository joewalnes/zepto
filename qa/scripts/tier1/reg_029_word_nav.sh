#!/usr/bin/env bash
# QA-REG-029: Alt+Right/Left word navigation
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-029: Word navigation"

file=$(qa_tmpfile_nl "reg029.txt" "hello world_foo bar")
qa_start "$file"

# Alt+Right past first word
qa_keys "alt-right" 0.2
qa_cursor_pos
col1="$QA_CURSOR_COL"

# Alt+Right past second word
qa_keys "alt-right" 0.2
qa_cursor_pos
col2="$QA_CURSOR_COL"

if [[ -n "$col1" && -n "$col2" && "$col2" -gt "$col1" ]]; then
    qa_pass "word nav progresses ($col1 → $col2)"
else
    qa_fail "word nav progresses (col1=$col1 col2=$col2)"
fi

# Alt+Left back
qa_keys "alt-left" 0.2
qa_cursor_pos
col3="$QA_CURSOR_COL"

if [[ -n "$col3" && "$col3" -lt "$col2" ]]; then
    qa_pass "word nav backwards ($col2 → $col3)"
else
    qa_fail "word nav backwards (col2=$col2 col3=$col3)"
fi

qa_keys "ctrl-q"
qa_summary
