#!/usr/bin/env bash
# QA-PAL-003: Command palette shows section headers
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-003: Palette sections"

qa_start

qa_keys "ctrl-space"
sleep 0.3

# Palette should show section headers like FILE, EDIT, VIEW, etc.
qa_screen
sections_found=0
for section in "FILE" "EDIT" "VIEW" "NAVIGATE"; do
    if echo "$QA_SCREEN" | grep -qi "$section"; then
        sections_found=$((sections_found + 1))
    fi
done

if [[ $sections_found -ge 2 ]]; then
    qa_pass "palette shows section headers ($sections_found found)"
else
    qa_fail "palette shows section headers (only $sections_found found)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
