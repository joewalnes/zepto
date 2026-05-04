#!/usr/bin/env bash
# QA-REG-045: Status bar shows "Commands" label with Ctrl+Space hint
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-045: Commands label on status bar"

file=$(qa_tmpfile_nl "reg045.txt" "hello")
qa_start "$file"

qa_assert_screen "Commands" "Commands pill visible in status bar"

qa_keys "ctrl-q"
qa_summary
