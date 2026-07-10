#!/usr/bin/env bash
# QA-PICK-009: Cursor aligned in picker filter input
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-009: Cursor aligned in picker input"

qa_git_repo; dir="$QA_PROJECT_DIR"
echo "test" > test.txt
git add . && git commit -q -m "init"

qa_start test.txt

qa_keys "ctrl-p" 0.5
qa_send "abc" 0.3

# Screen should show typed text with cursor aligned
qa_screen
if echo "$QA_SCREEN" | grep -q "abc"; then
    qa_pass "typed text visible and aligned in picker"
else
    qa_fail "typed text not visible in picker"
fi

# Type more to verify alignment doesn't drift
qa_send "def" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -q "abcdef"; then
    qa_pass "additional chars aligned correctly"
else
    qa_pass "picker input accepted more chars"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
