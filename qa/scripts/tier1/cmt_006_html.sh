#!/usr/bin/env bash
# QA-CMT-006: Toggle comment on HTML file uses <!-- -->
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-006: HTML comment style"

file=$(qa_tmpfile_nl "cmt006.html" "<p>hello</p>")
qa_start "$file"

qa_raw $'\x1f'
qa_assert_expect "<!--" "HTML comment opening visible"

qa_raw $'\x1f'
qa_assert_expect "<p>hello</p>" "uncommented back"

qa_keys "ctrl-q"
qa_summary
