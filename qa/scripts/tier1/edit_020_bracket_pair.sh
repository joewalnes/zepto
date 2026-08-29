#!/usr/bin/env bash
# QA-EDIT-020: Auto-closing bracket pairs
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-020: Bracket auto-close"

file=$(qa_tmpfile_nl "edit020.js" "")
qa_start "$file"

# Auto-pairs is ON by default (each test gets fresh state dir).
# Use expect-based waits, not fixed sleeps — this script flaked under
# full-suite parallel load when 0.2s wasn't enough for a render.

qa_send "(" 0.1
qa_assert_expect '\(\)' "( auto-closed with )"

qa_keys "end" 0.1
qa_keys "enter" 0.1
qa_send "{" 0.1
qa_assert_expect '\{\}' "{ auto-closed with }"

qa_keys "end" 0.1
qa_keys "enter" 0.1
qa_send "[" 0.1
qa_assert_expect '\[\]' "[ auto-closed with ]"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
