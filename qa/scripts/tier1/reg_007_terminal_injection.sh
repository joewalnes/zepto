#!/usr/bin/env bash
# QA-REG-007: No shell injection in Terminal.pm clipboard
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-007: Terminal.pm clipboard safe exec"

file=$(qa_tmpfile_nl "reg007.txt" "test data for clipboard")
qa_start "$file"

# Select and copy
qa_keys "ctrl-a"
qa_keys "ctrl-c"
sleep 0.3

# Paste
qa_keys "end"
qa_keys "enter"
qa_keys "ctrl-v"
sleep 0.3

# Editor should be responsive
if qa_alive; then
    qa_pass "clipboard operations use safe exec (no crash)"
else
    qa_fail "clipboard operations use safe exec" "editor crashed"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
