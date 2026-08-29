#!/usr/bin/env bash
# QA-NAV-002: Alt+Right moves cursor by word
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-002: Word-right navigation"

file=$(qa_tmpfile "nav002.txt" "hello world foo")
qa_start "$file"

qa_assert_expect "1:1" "starts at 1:1"

qa_keys "alt-right" 0.2
# Should have moved past "hello"
qa_assert_expect "1:[4-9]" "alt-right jumped past first word"

qa_keys "alt-right" 0.2
# Should have moved past "world"
qa_assert_expect "1:1[0-6]|1:[7-9]" "alt-right jumped past second word"

qa_keys "ctrl-q"
qa_summary
