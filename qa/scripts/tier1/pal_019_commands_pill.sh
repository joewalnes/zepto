#!/usr/bin/env bash
# QA-PAL-019: Palette pill always visible as rightmost pill
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-019: Commands pill in status bar"

file=$(qa_tmpfile_nl "pal019.txt" "hello")
qa_start "$file"

qa_assert_expect "Commands" "Commands pill visible in status bar"

qa_keys "ctrl-q"
qa_summary
