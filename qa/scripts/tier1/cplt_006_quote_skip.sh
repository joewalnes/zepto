#!/usr/bin/env bash
# QA-CPLT-006: Typing closing quote skips over auto-paired quote
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-006: Quote skip-over"

file=$(qa_tmpfile "cplt006.js" "")
qa_start "$file"

# Type opening quote — auto-pairs to ""
qa_send "\""

# Type content inside quotes
qa_send "hello"

# Type closing quote — should skip over
qa_send "\""

qa_screen
# Should see "hello" not "hello""
if echo "$QA_SCREEN" | grep -qF '"hello"'; then
    qa_pass "closing quote skipped over, result is \"hello\""
else
    qa_fail "closing quote skipped over" "expected \"hello\""
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
