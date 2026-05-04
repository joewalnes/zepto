#!/usr/bin/env bash
# QA-CMT-010: Minimum indent alignment for comment
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-010: Comment minimum indent alignment"

file=$(qa_tmpfile_nl "cmt010.py" "def foo():
    x = 1
      y = 2")
qa_start "$file"

# Select all 3 lines
qa_keys "ctrl-a"

# Toggle comment
qa_raw $'\x1f'

# All # should be at minimum indent (col 1 = def foo line)
qa_assert_screen "# def foo" "comment at minimum indent"
qa_assert_screen "#     x = 1" "indented line has comment at min indent"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
