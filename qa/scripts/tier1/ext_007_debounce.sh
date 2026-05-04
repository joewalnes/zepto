#!/usr/bin/env bash
# QA-EXT-007: mtime polling debounced
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EXT-007: Debounced polling"
file=$(qa_tmpfile_nl "ext007.txt" "content")
qa_start "$file"
# Rapid typing shouldn't trigger constant mtime checks
for i in $(seq 1 20); do qa_send "x" 0.05; done
sleep 0.3
if qa_alive; then
    qa_pass "editor responsive during rapid input (debounced)"
else
    qa_fail "editor responsive during rapid input"
fi
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
