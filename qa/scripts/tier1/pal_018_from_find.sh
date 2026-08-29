#!/usr/bin/env bash
# QA-PAL-018: Palette always accessible from any state
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-018: Palette accessible from find bar"

file=$(qa_tmpfile_nl "pal018.txt" "hello world")
qa_start "$file"

# Open find bar
qa_keys "ctrl-f"
qa_assert_expect "Find" "find bar open"

# Open palette from find bar
qa_keys "ctrl-space"
sleep 0.3

qa_assert_expect "Commands" "palette opened from find bar state"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
