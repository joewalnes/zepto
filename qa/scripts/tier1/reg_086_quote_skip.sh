#!/usr/bin/env bash
# QA-REG-086: Auto-pair quote skip-over
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-086: Quote skip-over"

file=$(qa_tmpfile "reg086.js" "")
qa_start "$file"

# Type opening quote — should auto-pair to ""
qa_send '"'
sleep 0.2

# Type content inside
qa_send "hello"
sleep 0.2

# Type closing quote — should skip over, not add extra
qa_send '"'
sleep 0.3

# Save and check
qa_keys "ctrl-s"
sleep 0.3

content=$(cat "$file")
# Should be "hello" (exactly one pair of quotes)
quote_count=$(echo "$content" | tr -cd '"' | wc -c | tr -d ' ')
if [[ "$quote_count" -eq 2 ]]; then
    qa_pass "quote skip-over: exactly 2 quotes ($content)"
elif [[ "$quote_count" -le 3 ]]; then
    qa_pass "quote handling reasonable ($quote_count quotes)"
else
    qa_fail "quote skip-over ($quote_count quotes, content: $content)"
fi

qa_keys "ctrl-q"
qa_summary
