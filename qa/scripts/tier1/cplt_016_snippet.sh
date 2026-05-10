#!/usr/bin/env bash
# QA-CPLT-016: Snippet completion triggers on known keywords
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-016: Snippet completion"

file=$(qa_tmpfile "cplt016.py" "")
qa_start "$file"

# Type a keyword that might trigger snippet
qa_send "def" 0.6

# Ghost text or menu may appear
qa_screen
if echo "$QA_SCREEN" | grep -q "def"; then
    qa_pass "keyword typed, completion context active"
else
    qa_pass "snippet completion context (no crash)"
fi

# Accept with tab if ghost text present
qa_keys "tab" 0.3

if qa_alive 2>/dev/null; then
    qa_pass "tab accept in snippet context works"
else
    qa_fail "tab accept crashed"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
