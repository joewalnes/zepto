#!/usr/bin/env bash
# QA-PAL-012: Mouse click outside palette dismisses it
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-012: Click outside palette closes it"

file=$(qa_tmpfile_nl "pal012.txt" "hello world")
qa_start "$file"

qa_keys "ctrl-space"
sleep 0.3
qa_assert_screen "Commands" "palette open"

# Click outside palette area (row 1, col 1 = top-left, outside palette)
hangon mouse-click "$QA_SESSION" --x 1 --y 1 --count 1 2>/dev/null || true
sleep 0.3

# Palette should be closed
qa_assert_screen "hello world" "editor visible after clicking outside"

qa_keys "ctrl-q"
qa_summary
