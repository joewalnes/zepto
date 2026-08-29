#!/usr/bin/env bash
# QA-REG-048: Palette reorganized into FILE/EDIT/NAVIGATE/VIEW sections
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-048: Palette has section headers"

file=$(qa_tmpfile_nl "reg048.txt" "hello")
qa_start "$file"

# Open command palette
qa_keys "ctrl-space"
sleep 0.5

qa_wait_screen 'FILE|EDIT|NAVIGATE|VIEW' || true
found=0
for section in FILE EDIT NAVIGATE VIEW; do
    if echo "$QA_SCREEN" | grep -q "$section"; then
        found=$((found + 1))
    fi
done

if [[ $found -ge 2 ]]; then
    qa_pass "palette shows section headers ($found found)"
else
    qa_fail "palette shows section headers" "only $found sections found"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
