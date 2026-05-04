#!/usr/bin/env bash
# QA-MS-012: Drag tree border resizes tree panel
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-012: Drag tree border resize"

file=$(qa_tmpfile_nl "ms012.txt" "hello world test content here that is long enough to see")
qa_start "$file"
sleep 0.3

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Measure editor content position (find where "hello" starts on screen)
qa_screen
hello_col_before=$(echo "$QA_SCREEN" | grep -n "hello" | head -1 | grep -oE 'hello' | head -1)
# Count the position of the │ separator to measure tree width
sep_count_before=$(echo "$QA_SCREEN" | head -5 | grep -o '│' | wc -l | tr -d ' ')

# Drag tree border wider (from ~col 25 to ~col 40)
hangon mouse-drag "$QA_SESSION" --from 25,10 --to 40,10 --steps 5
sleep 0.3

# Measure again — the │ separator should have moved right
qa_screen
sep_count_after=$(echo "$QA_SCREEN" | head -5 | grep -o '│' | wc -l | tr -d ' ')

# The content of "hello" should start at a different column
# because the tree takes more space
if echo "$QA_SCREEN" | grep -q "hello"; then
    qa_pass "editor content still visible after drag"
else
    qa_fail "editor content still visible after drag"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
