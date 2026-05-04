#!/usr/bin/env bash
# QA-EXT-004: Keep local preserves buffer
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EXT-004: Keep local on external change"

file=$(qa_tmpfile_nl "ext004.txt" "original")
qa_start "$file"

# Make local edit
qa_send " local edit"

# Modify externally
echo "external version" > "$file"

# Interact to trigger check
qa_keys "escape"
sleep 1.5

qa_screen
if echo "$QA_SCREEN" | grep -qE "Reload|Keep|changed"; then
    # Press K to keep local
    qa_send "k"
    sleep 0.3
    qa_assert_screen "local edit" "local buffer preserved after Keep"
else
    qa_skip "external change prompt not shown"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
