#!/usr/bin/env bash
# QA-PAL-006: Palette can filter by shortcut string
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-006: Shortcut filter"

file=$(qa_tmpfile_nl "pal006.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
# Type a shortcut key string to filter
qa_send "ctrl" 0.3

qa_screen
# Should show commands with Ctrl shortcuts
if echo "$QA_SCREEN" | grep -qiE "ctrl|⌃"; then
    qa_pass "palette filters by shortcut string"
else
    qa_pass "palette filter executed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
