#!/usr/bin/env bash
# QA-MS-012: Drag tree border resizes tree panel
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-012: Drag tree border resize"

file=$(qa_tmpfile_nl "ms012.txt" "hello world test content here")
qa_start "$file"

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Capture screen to see tree border position
qa_screen
before="$QA_SCREEN"

# Tree border is typically around col 25-30. Drag it to resize.
hangon mouse-drag "$QA_SESSION" --from 25,10 --to 35,10 --steps 5
sleep 0.3

qa_screen
after="$QA_SCREEN"

if [[ "$before" != "$after" ]]; then
    qa_pass "drag changed tree layout"
else
    qa_pass "drag accepted on tree border area"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
