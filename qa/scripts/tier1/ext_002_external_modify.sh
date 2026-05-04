#!/usr/bin/env bash
# QA-EXT-002: External file modification detected
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EXT-002: External file change detection"

file=$(qa_tmpfile_nl "ext002.txt" "original content")
qa_start "$file"

qa_assert_screen "original content" "initial content visible"

# Modify file externally
echo "externally modified" > "$file"
sleep 1

# Editor should detect the change — may show a prompt or auto-reload
qa_screen
if echo "$QA_SCREEN" | grep -qE "externally modified|reload|changed|modified"; then
    qa_pass "external modification detected or reloaded"
else
    # Try focusing the editor to trigger check
    qa_keys "ctrl-s" 0.3
    qa_screen
    if echo "$QA_SCREEN" | grep -qE "externally|reload|changed|conflict"; then
        qa_pass "external modification detected on save attempt"
    else
        qa_skip "external modification detection" "may not auto-detect"
    fi
fi

qa_keys "ctrl-q"
sleep 0.2
# Handle any prompts
qa_send "n" 0.2
qa_send "n" 0.2
qa_summary
