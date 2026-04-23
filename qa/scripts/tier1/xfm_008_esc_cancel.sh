#!/usr/bin/env bash
# QA-XFM-008: Esc cancels transform
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-008: Transform Esc cancels"

file=$(qa_tmpfile_nl "xfm008.txt" "original text")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
qa_send "sort" 0.2
qa_keys "escape"

qa_assert_screen "original text" "buffer unchanged after Esc"

qa_keys "ctrl-q"
qa_summary
