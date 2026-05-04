#!/usr/bin/env bash
# QA-REG-026: Alt+D diff toggle doesn't crash without git
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-026: Diff toggle no-crash without git"

file=$(qa_tmpfile_nl "reg026.txt" "not in a git repo")
qa_start "$file"

# Toggle diff — should not crash even without git
qa_keys "alt-d"
sleep 0.3

if qa_alive; then
    qa_pass "diff toggle without git didn't crash"
else
    qa_fail "diff toggle without git crashed"
fi

qa_keys "ctrl-q"
qa_summary
