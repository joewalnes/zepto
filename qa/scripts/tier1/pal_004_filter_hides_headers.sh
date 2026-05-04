#!/usr/bin/env bash
# QA-PAL-004: Palette filter hides section headers
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-004: Palette filter hides headers"

file=$(qa_tmpfile_nl "pal004.txt" "hello")
qa_start "$file"

# Open palette with empty query — headers should be visible
qa_keys "ctrl-space"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qE "FILE|EDIT|NAVIGATE|VIEW"; then
    qa_pass "section headers visible with empty query"
else
    qa_fail "section headers visible with empty query"
fi

# Type a filter — headers should be hidden
qa_send "save" 0.3

qa_screen
# With a filter active, section headers like FILE, EDIT should not show
# (only matching commands should appear)
has_headers=false
if echo "$QA_SCREEN" | grep -qE "^[[:space:]]*(FILE|EDIT|NAVIGATE|VIEW)[[:space:]]*$"; then
    has_headers=true
fi

if [[ "$has_headers" == "false" ]]; then
    qa_pass "section headers hidden when filter active"
else
    qa_fail "section headers hidden when filter active" "headers still visible"
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
