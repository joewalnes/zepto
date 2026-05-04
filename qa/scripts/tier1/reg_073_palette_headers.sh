#!/usr/bin/env bash
# QA-REG-073: Palette section headers visible
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-073: Palette section headers"

file=$(qa_tmpfile_nl "reg073.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
sleep 0.5

# Check for section headers
qa_screen
headers_found=0
for header in "FILE" "EDIT" "NAVIGATE" "VIEW" "File" "Edit" "Navigate" "View"; do
    if echo "$QA_SCREEN" | grep -q "$header"; then
        headers_found=$((headers_found + 1))
    fi
done

if [[ $headers_found -ge 2 ]]; then
    qa_pass "palette section headers visible ($headers_found found)"
else
    qa_fail "palette section headers visible" "only $headers_found found"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
