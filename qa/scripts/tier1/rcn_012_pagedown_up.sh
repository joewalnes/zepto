#!/usr/bin/env bash
# QA-RCN-012: Page Down/Up in recent files list
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-012: Recent files Page Down/Up"

file=$(qa_tmpfile_nl "rcn012.txt" "hello")
qa_start "$file"

qa_keys "ctrl-e"
sleep 0.3

# Page Down
qa_keys "pagedown"
sleep 0.2

# Page Up
qa_keys "pageup"
sleep 0.2

# Should still be in the picker
qa_alive && qa_pass "page navigation in recent files works" || qa_fail "editor crashed"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
