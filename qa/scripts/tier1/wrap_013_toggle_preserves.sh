#!/usr/bin/env bash
# QA-WRAP-013: Toggle wrap doesn't reorder text
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-013: Wrap toggle preserves text"

file=$(qa_tmpfile_nl "wrap013.txt" "line one
line two
line three")
qa_start "$file"

# Toggle wrap on then off
qa_keys "alt-z"
sleep 0.3
qa_keys "alt-z"
sleep 0.3

# Verify text unchanged
qa_assert_expect "line one" "line one preserved"
qa_assert_expect "line two" "line two preserved"
qa_assert_expect "line three" "line three preserved"

qa_keys "ctrl-q"
qa_summary
