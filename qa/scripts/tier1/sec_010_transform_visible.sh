#!/usr/bin/env bash
# QA-SEC-010: Shell transform command visible to user
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-010: Transform command visible to user"

file=$(qa_tmpfile_nl "sec010.txt" "hello world
foo bar baz")
qa_start "$file"

# Select text
qa_keys "ctrl-a"

# Open transform
qa_keys "alt-t"
sleep 0.3

# The transform input should be visible — user must type the command
qa_assert_screen "Transform|transform|Shell|shell|\|" "transform input prompt visible"

# Cancel without executing
qa_keys "escape"

qa_pass "transform requires explicit user command input"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
