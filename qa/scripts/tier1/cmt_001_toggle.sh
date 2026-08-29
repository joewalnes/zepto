#!/usr/bin/env bash
# QA-CMT-001+002: Toggle comment adds and removes comment prefix
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-001: Toggle comment"

file=$(qa_tmpfile_nl "cmt001.py" "x = 1
y = 2")
qa_start "$file"

# Toggle comment on line 1 (Ctrl+/ = 0x1f)
qa_raw $'\x1f'
qa_assert_expect "# x = 1" "comment added to line 1"

# Toggle again to uncomment
qa_raw $'\x1f'
qa_assert_expect "x = 1" "comment removed from line 1"
qa_assert_not_screen "# x" "no comment prefix"

qa_keys "ctrl-q"
qa_summary
