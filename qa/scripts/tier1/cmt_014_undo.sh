#!/usr/bin/env bash
# QA-CMT-014: Undo a comment toggle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-014: Comment undo"

file=$(qa_tmpfile_nl "cmt014.py" "x = 1")
qa_start "$file"

qa_raw $'\x1f'
qa_assert_expect "# x = 1" "commented"

qa_keys "ctrl-z"
qa_assert_expect "x = 1" "comment undone"
qa_assert_not_screen "# x" "no comment prefix"

qa_keys "ctrl-q"
qa_summary
