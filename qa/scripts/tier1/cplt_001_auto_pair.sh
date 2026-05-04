#!/usr/bin/env bash
# QA-CPLT-001+002+003+004: Auto-pair brackets and quotes
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-001: Auto-pair brackets"

file=$(qa_tmpfile "cplt001.js" "")
qa_start "$file"

# Ensure auto-pairs is ON
qa_keys "ctrl-space"
qa_send "auto pair" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -q '\[off\]'; then
    qa_keys "enter" 0.3
    qa_keys "escape" 0.2
    qa_keys "escape" 0.2
else
    qa_keys "escape" 0.2
    qa_keys "escape" 0.2
fi
sleep 0.3

# Type opening paren
qa_send "("
qa_screen
if echo "$QA_SCREEN" | grep -qF "()"; then
    qa_pass "( auto-paired to ()"
else
    qa_fail "( auto-paired to ()"
fi

# Type opening brace
qa_keys "end"
qa_send "{"
qa_screen
if echo "$QA_SCREEN" | grep -qF "{}"; then
    qa_pass "{ auto-paired to {}"
else
    qa_fail "{ auto-paired to {}"
fi

# Type opening bracket
qa_keys "end"
qa_send "["
qa_screen
if echo "$QA_SCREEN" | grep -qF "[]"; then
    qa_pass "[ auto-paired to []"
else
    qa_fail "[ auto-paired to []"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
