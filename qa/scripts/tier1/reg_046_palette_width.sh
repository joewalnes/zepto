#!/usr/bin/env bash
# QA-REG-046: Palette max width at wide terminals
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-046: Palette width limit"

file=$(qa_tmpfile_nl "reg046.txt" "test content")
qa_start "$file"

qa_keys "ctrl-space" 0.3

qa_assert_expect "command|save|new|file" "palette rendered at appropriate width"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
