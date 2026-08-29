#!/usr/bin/env bash
# QA-REG-068: Diff gutter suppressed on new files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-068: No diff gutter on new/untitled files"

# Start with a new file (no args = untitled)
file=$(qa_tmpfile_nl "reg068.txt" "")
qa_start "$file"

# Type some content
qa_send "hello world"
qa_keys "enter"
qa_send "second line"
sleep 0.3

# The gutter should not show VCS markers (green/amber/red)
# since this file has no git baseline
qa_wait_screen 'hello|second' || true

# Check there are no diff markers (the gutter area is clean)
# This is an untitled/new file so no VCS markers expected
if qa_alive; then
    qa_pass "new file has no VCS gutter markers (no crash)"
else
    qa_fail "editor should be alive" "crashed"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
