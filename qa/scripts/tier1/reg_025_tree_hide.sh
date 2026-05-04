#!/usr/bin/env bash
# QA-REG-025: Tree hide via --no-tree flag
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-025: Tree hide via CLI flag"

file=$(qa_tmpfile_nl "reg025.txt" "test content")
qa_start --no-tree "$file"

# With --no-tree, file tree should not be visible
qa_screen
initial="$QA_SCREEN"

# Toggle tree on with Ctrl+B
qa_keys "ctrl-b"
qa_screen
toggled="$QA_SCREEN"

if [[ "$initial" != "$toggled" ]]; then
    qa_pass "Ctrl+B toggled tree visibility"
else
    qa_fail "Ctrl+B toggled tree visibility" "screen unchanged"
fi

qa_keys "ctrl-q"
qa_summary
