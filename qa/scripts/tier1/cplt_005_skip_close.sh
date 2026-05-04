#!/usr/bin/env bash
# QA-CPLT-005: Typing closing paren skips over auto-paired one
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-005: Skip over auto-paired closing paren"

file=$(qa_tmpfile "cplt005.js" "")
qa_start "$file"

# Type opening paren — should auto-pair to ()
qa_send "("

# Type closing paren — should skip over, not insert second
qa_send ")"

qa_screen
# Should see exactly "()" not "())"
line=$(echo "$QA_SCREEN" | head -5 | grep -oE '\(\)+' | head -1 || true)
if [[ "$line" == "()" ]]; then
    qa_pass "closing paren skipped over auto-paired )"
else
    # Check no double close
    if echo "$QA_SCREEN" | grep -qF "())"; then
        qa_fail "closing paren skipped over auto-paired )" "found ()) on screen"
    else
        qa_pass "closing paren handled correctly"
    fi
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
