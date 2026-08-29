#!/usr/bin/env bash
# QA-REG-017: Transform via shell (Alt+T)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-017: Transform via shell"

file=$(qa_tmpfile_nl "reg017.txt" "cherry
apple
banana")
qa_start "$file"

# Select all text
qa_keys "ctrl-a"

# Open transform
qa_keys "alt-t"
qa_assert_expect "Shell|sort|command|pipe|Transform" "transform prompt visible"

# Type sort command and execute
qa_keys "ctrl-a" 0.1
qa_send "sort" 0.2
qa_keys "enter"
sleep 0.5

qa_assert_expect "apple" "sort result: apple present"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
