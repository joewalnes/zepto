#!/usr/bin/env bash
# QA-CPLT-008: Backspace removes both chars of auto-pair
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-008: Backspace deletes auto-pair"

file=$(qa_tmpfile "cplt008.js" "")
qa_start "$file"

# Type opening paren — auto-pairs to ()
qa_send "("

qa_assert_expect "\\(\\)" "auto-pair created ()"

# Backspace should remove both ( and )
qa_keys "backspace"

qa_screen
if echo "$QA_SCREEN" | grep -qF "()"; then
    qa_fail "backspace removed both chars" "() still present"
else
    qa_pass "backspace removed both chars of auto-pair"
fi

qa_keys "ctrl-q"
qa_summary
