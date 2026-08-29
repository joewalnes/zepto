#!/usr/bin/env bash
# QA-PAL-023: Home/End in command palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-023: Palette Home/End navigation"

file=$(qa_tmpfile_nl "pal023.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
sleep 0.3

# Navigate down a bit
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_keys "down" 0.1

# End should jump to last command
qa_keys "end"
sleep 0.3

# Home should jump back to first
qa_keys "home"
sleep 0.3

qa_assert_expect "Commands" "palette responsive after Home/End"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
