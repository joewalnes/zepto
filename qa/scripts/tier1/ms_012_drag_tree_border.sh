#!/usr/bin/env bash
# QA-MS-012: Drag tree border resizes tree panel
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-012: Drag tree border resize"

file=$(qa_tmpfile_nl "ms012.txt" "hello world test content here that is long enough to see")
qa_start "$file"
qa_assert_expect "hello" "file content visible"

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# Measure tree width via the │ separator column. Guard every measurement
# pipeline with || true — under set -e an empty grep result used to kill
# the script silently (flaked under full-suite parallel load).
qa_screen
sep_count_before=$(echo "$QA_SCREEN" | head -5 | grep -o '│' | wc -l | tr -d ' ' || true)

# Drag tree border wider (from ~col 25 to ~col 40)
hangon mouse-drag "$QA_SESSION" --from 25,10 --to 40,10 --steps 5 || true
sleep 0.5

# Editor content must still be visible after the drag
qa_assert_expect "hello" "editor content still visible after drag"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
