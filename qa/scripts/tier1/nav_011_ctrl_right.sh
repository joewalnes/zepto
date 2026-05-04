#!/usr/bin/env bash
# QA-NAV-011: Alt+Right jumps to next word boundary
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-011: Alt+Right word jump"

file=$(qa_tmpfile_nl "nav011.txt" "alpha beta gamma delta")
qa_start "$file"

# Alt+Right should jump past first word
qa_keys "alt-right" 0.2

qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -ge 5 ]]; then
    qa_pass "alt-right jumped past first word (col $QA_CURSOR_COL)"
else
    qa_fail "alt-right jumped past first word (col $QA_CURSOR_COL)"
fi

# Two more jumps
qa_keys "alt-right" 0.1
qa_keys "alt-right" 0.1

qa_cursor_pos
if [[ -n "$QA_CURSOR_COL" && "$QA_CURSOR_COL" -ge 15 ]]; then
    qa_pass "three alt-right jumps reached col $QA_CURSOR_COL"
else
    qa_fail "three alt-right jumps (col $QA_CURSOR_COL)"
fi

qa_keys "ctrl-q"
qa_summary
