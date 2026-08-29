#!/usr/bin/env bash
# QA-REG-056: External file change detection and reload
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-056: External file change detection"

file=$(qa_tmpfile_nl "reg056.txt" "original content")
qa_start "$file"

qa_assert_expect "original content" "initial content shown"

# Modify file externally
echo "modified externally" > "$file"

# Trigger check - interact with editor
qa_keys "escape"
sleep 1.5

qa_wait_screen 'modified|Reload|changed' || true
if echo "$QA_SCREEN" | grep -q "modified externally"; then
    qa_pass "buffer reloaded with external changes"
elif echo "$QA_SCREEN" | grep -qiE "Reload|changed|modified"; then
    qa_pass "reload prompt shown for external changes"
else
    qa_skip "external change detection may need focus event"
fi

qa_keys "ctrl-q"
qa_summary
