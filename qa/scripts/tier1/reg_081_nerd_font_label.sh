#!/usr/bin/env bash
# QA-REG-081: "Nerd Font" label (not "Powerline") in palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-081: Nerd Font label in palette"

file=$(qa_tmpfile_nl "reg081.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
sleep 0.5

# Type to filter for nerd font
qa_send "nerd" 0.3

qa_wait_screen 'Nerd|Powerline' || true
if echo "$QA_SCREEN" | grep -qiE "Nerd Font|nerd font"; then
    qa_pass "palette shows 'Nerd Font' label"
elif echo "$QA_SCREEN" | grep -qiE "Powerline|powerline"; then
    qa_fail "palette shows 'Nerd Font' label" "still showing 'Powerline'"
else
    qa_skip "could not find nerd font entry" "may need different filter"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
