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

# Should see "hello" not "hello""
qa_assert_expect '"hello"' "closing quote skipped over, result is \"hello\""

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
