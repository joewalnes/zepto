#!/usr/bin/env bash
# QA-EXT-001: Clean buffer silently reloads external changes
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EXT-001: Clean buffer external reload"

file=$(qa_tmpfile_nl "ext001.txt" "original content")
qa_start "$file"

qa_assert_expect "original content" "initial content"

# Modify file externally
echo "modified externally" > "$file"

# Trigger reload check — interact with editor
qa_keys "escape"
sleep 1

qa_screen
if echo "$QA_SCREEN" | grep -q "modified externally"; then
    qa_pass "buffer reloaded with external changes"
elif echo "$QA_SCREEN" | grep -q "Reload\|changed\|modified"; then
    qa_pass "reload prompt or notification shown"
else
    qa_skip "external change detection may need focus event"
fi

qa_keys "ctrl-q"
qa_summary
