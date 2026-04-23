#!/usr/bin/env bash
# QA-CMT-005: Toggle comment uses // for JavaScript
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-005: JS comment style"

file=$(qa_tmpfile_nl "cmt005.js" "const x = 1;")
qa_start "$file"

qa_raw $'\x1f'
qa_assert_screen "// const x = 1;" "JS line commented with //"

qa_raw $'\x1f'
qa_assert_screen "const x = 1;" "uncommented back"

qa_keys "ctrl-q"
qa_summary
