#!/usr/bin/env bash
# QA-PAL-005: Fuzzy matching in command palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-005: Palette fuzzy matching"

file=$(qa_tmpfile_nl "pal005.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "tgcm" 0.3

qa_assert_expect "Comment|comment" "fuzzy match found Toggle Comment"

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
