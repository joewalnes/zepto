#!/usr/bin/env bash
# QA-CMT-004: Toggle comment on .sh file uses # prefix
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-004: Shell comment style"

file=$(qa_tmpfile_nl "cmt004.sh" "echo hello")
qa_start "$file"

qa_raw $'\x1f'
qa_assert_expect "# echo hello" "shell line commented with #"

qa_raw $'\x1f'
qa_assert_expect "echo hello" "uncommented back"
qa_assert_not_screen "# echo" "no comment prefix remains"

qa_keys "ctrl-q"
qa_summary
