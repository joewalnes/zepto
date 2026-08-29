#!/usr/bin/env bash
# QA-CPLT-004: Double-quote auto-pairs in JS file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-004: Quote auto-pair"

file=$(qa_tmpfile "cplt004.js" "")
qa_start "$file"

# Type a double-quote
qa_send "\""

qa_assert_expect '""' "double-quote auto-paired to \"\""

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
