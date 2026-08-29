#!/usr/bin/env bash
# QA-PRMT-007: Prompt persists until resolved (not time-based)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-007: Prompt persists"

file=$(qa_tmpfile_nl "prmt007.txt" "original")
qa_start "$file"

qa_send "dirty edit"

# Trigger save prompt
qa_keys "ctrl-q"
sleep 0.3
qa_assert_expect "Save|Discard|Cancel" "prompt visible"

# Wait 3 seconds
sleep 3

# Prompt should still be visible
qa_assert_expect "Save|Discard|Cancel" "prompt persists after 3 seconds"

# Cancel
qa_send "c" 0.3

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
