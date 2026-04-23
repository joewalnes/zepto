#!/usr/bin/env bash
# QA-FIND-013: Ctrl+J/K navigate matches after find closed
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-013: Ctrl+J/K navigate after find"

content=""
for i in $(seq 1 50); do content+="line $i text"$'\n'; done
content+="MARKER target here"$'\n'
for i in $(seq 52 100); do content+="line $i text"$'\n'; done
file=$(qa_tmpfile_nl "find013.txt" "$content")
qa_start "$file"

# Find MARKER and close
qa_keys "ctrl-f"
qa_send "MARKER" 0.3
qa_keys "escape"

# Should have jumped to MARKER
qa_assert_screen "MARKER" "found and jumped to MARKER"

qa_keys "ctrl-q"
qa_summary
