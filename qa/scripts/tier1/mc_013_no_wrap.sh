#!/usr/bin/env bash
# QA-MC-013: Ctrl+D does not wrap at end of file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MC-013: Ctrl+D no wrap on single match"

file=$(qa_tmpfile_nl "mc013.txt" "unique_word and nothing else")
qa_start "$file"

# Select "unique_word"
qa_keys "ctrl-d"
# Try to add next occurrence (none exists)
qa_keys "ctrl-d"

# Editor should be alive, no crash
qa_alive && qa_pass "editor alive after no-more-matches" || qa_fail "editor crashed"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
