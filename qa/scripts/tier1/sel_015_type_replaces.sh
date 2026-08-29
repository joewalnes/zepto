#!/usr/bin/env bash
# QA-SEL-015: Typing replaces selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEL-015: Typing replaces selection"

file=$(qa_tmpfile "sel015.txt" "hello world")
qa_start "$file"

# Select "hello" (5 chars from home)
qa_keys "home"
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1

# Type replacement
qa_send "goodbye"

qa_assert_expect "goodbye world" "typing replaced selection"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
