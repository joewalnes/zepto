#!/usr/bin/env bash
# QA-HELP-001: F1 opens tutorial
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-HELP-001: F1 opens tutorial"

file=$(qa_tmpfile_nl "help001.txt" "hello")
qa_start "$file"

qa_keys "f1"
sleep 0.5

qa_assert_screen "Zepto|Tutorial|Getting Started|Welcome" "tutorial content visible"

qa_keys "ctrl-w"
qa_keys "ctrl-q"
qa_summary
