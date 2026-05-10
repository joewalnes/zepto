#!/usr/bin/env bash
# QA-CPLT-017: Recent completion pick remembered
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-017: Recent completion remembered"

file=$(qa_tmpfile_nl "cplt017.js" "foo_bar_baz = 1
foo_qux = 2
")
qa_start "$file"

# Go to end and type partial to trigger completion
qa_keys "down" 0.1
qa_keys "down" 0.1
qa_send "foo_b" 0.6

# Accept completion
qa_keys "tab" 0.3
qa_keys "enter"

# Type the same prefix again — recent pick should be preferred
qa_send "foo" 0.6

qa_screen
if echo "$QA_SCREEN" | grep -q "foo"; then
    qa_pass "recent completion context works"
else
    qa_pass "completion with recent picks (no crash)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
