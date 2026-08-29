#!/usr/bin/env bash
# QA-REG-005: Global shortcuts work from find bar
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-005: Global shortcuts from find bar"

file=$(qa_tmpfile_nl "reg005.txt" "hello world")
qa_start "$file"

# Open find bar
qa_keys "ctrl-f"
qa_assert_expect "Find|find|Search" "find bar open"

# Ctrl+N should open new tab even from find bar
qa_keys "ctrl-n"
sleep 0.5

qa_assert_expect "untitled|Untitled" "Ctrl+N opened new tab from find bar"

qa_keys "ctrl-q"
qa_summary
