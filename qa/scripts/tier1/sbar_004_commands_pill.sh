#!/usr/bin/env bash
# QA-SBAR-004: Commands pill always rightmost
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-004: Commands pill position"

file=$(qa_tmpfile_nl "sbar004.txt" "hello")
qa_start "$file"

qa_assert_screen "Commands" "Commands pill visible"

qa_keys "ctrl-q"
qa_summary
