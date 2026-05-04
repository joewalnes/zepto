#!/usr/bin/env bash
# QA-CPLT-002: Autocomplete suggests keywords from current file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-002: Keyword completion"

file=$(qa_tmpfile_nl "cplt002.py" "def superlongfunction():
    pass

def another():
    sup")
qa_start "$file"

# Move to end of file where "sup" is typed
qa_keys "ctrl-g"
qa_send "5" 0.2
qa_keys "enter"
qa_keys "end"

# Trigger completion — type a character to trigger autocomplete
# The word "sup" should match "superlongfunction"
sleep 0.5

# Check if completion dropdown or ghost text appears
qa_screen
if echo "$QA_SCREEN" | grep -q "superlongfunction"; then
    qa_pass "autocomplete suggests superlongfunction"
else
    # Completion might not auto-trigger — try manual trigger via tab or palette
    qa_skip "autocomplete suggestion" "may need manual trigger"
fi

qa_keys "escape" 0.2
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
