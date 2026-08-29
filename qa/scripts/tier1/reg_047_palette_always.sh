#!/usr/bin/env bash
# QA-REG-047: Palette accessible from any state
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-047: Palette from any state"

file=$(qa_tmpfile_nl "reg047.txt" "hello")
qa_start "$file"

# From find bar
qa_keys "ctrl-f"
sleep 0.2
qa_keys "ctrl-space"
sleep 0.3
qa_assert_expect "Commands" "palette opens from find bar"
qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# From goto
qa_keys "ctrl-g"
sleep 0.2
qa_keys "ctrl-space"
sleep 0.3
qa_assert_expect "Commands" "palette opens from goto"
qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "escape" 0.2

qa_keys "ctrl-q"
qa_summary
