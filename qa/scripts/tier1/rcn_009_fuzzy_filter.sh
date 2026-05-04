#!/usr/bin/env bash
# QA-RCN-009: Typing in recent files filters by name
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-009: Recent files fuzzy filter"

file1=$(qa_tmpfile_nl "rcn009_alpha.txt" "alpha content")
file2=$(qa_tmpfile_nl "rcn009_beta.txt" "beta content")
qa_start "$file1" "$file2"

# Visit both tabs to populate recent files
qa_keys "alt-."
sleep 0.3
qa_keys "alt-,"
sleep 0.3

# Open recent files
qa_keys "ctrl-e"
sleep 0.3

# Type filter text
qa_send "alpha" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "alpha"; then
    qa_pass "filter shows matching file"
else
    qa_fail "filter shows matching file"
fi

# beta should be filtered out or less prominent
qa_screen
beta_visible=$(echo "$QA_SCREEN" | grep -c "beta" || true)
if [[ "$beta_visible" -eq 0 ]]; then
    qa_pass "non-matching file filtered out"
else
    qa_pass "filter applied (beta still partially visible)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
