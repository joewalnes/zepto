#!/usr/bin/env bash
# QA-REG-038: Toggle comment Ctrl+/ for various languages
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-038: Toggle comment Ctrl+/"

# Test Python commenting
file=$(qa_tmpfile_nl "reg038.py" "x = 1
y = 2")
qa_start "$file"

# Toggle comment (Ctrl+/ = 0x1f)
qa_raw $'\x1f'
qa_assert_expect "# x = 1" "Python comment added"

# Uncomment
qa_raw $'\x1f'
qa_assert_expect "x = 1" "Python comment removed"
qa_assert_not_screen "# x" "no comment prefix remains"

qa_keys "ctrl-q"
qa_summary
