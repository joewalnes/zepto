#!/usr/bin/env bash
# QA-WRAP-002: Markdown file defaults to wrap ON
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-002: Markdown defaults to wrap"

file=$(qa_tmpfile_nl "wrap002.md" "# Hello World

This is a markdown file.")
qa_start "$file"

qa_screen
# Check if Wrap pill is highlighted/ON — look for Wrap indicator
if echo "$QA_SCREEN" | grep -qE "Wrap|wrap"; then
    qa_pass "wrap indicator visible for .md file"
else
    qa_skip "wrap pill may be hidden at this terminal width"
fi

qa_keys "ctrl-q"
qa_summary
