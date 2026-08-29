#!/usr/bin/env bash
# QA-CMT-007: Toggle comment on CSS file uses /* */
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-007: CSS comment style"

file=$(qa_tmpfile_nl "cmt007.css" "body { color: red; }")
qa_start "$file"

qa_raw $'\x1f'
qa_assert_expect "/\\*" "CSS comment opening visible"

qa_raw $'\x1f'
qa_assert_expect "body" "uncommented back"

qa_keys "ctrl-q"
qa_summary
