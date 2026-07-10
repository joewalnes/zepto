#!/usr/bin/env bash
# QA-EDIT-020: Auto-closing bracket pairs
#
# Uses qa_expect_screen (poll-until-rendered) instead of fixed short sleeps:
# under `make qa`'s 4-way parallel load, a 0.2s sleep between keystroke and
# screen capture is not always enough for the render to land, which made
# this test flaky in full runs while passing standalone. The product
# behavior itself is solid — verified 8x in parallel during the Phase 1
# investigation (see bugs.md "hangon's shared state.json..." entry for the
# other, unrelated cause of this script's historical baseline failure).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-020: Bracket auto-close"

file=$(qa_tmpfile_nl "edit020.js" "")
qa_start "$file"

# Auto-pairs is ON by default (each test gets fresh state dir)
sleep 0.3

# Type opening bracket — should auto-insert closing bracket
qa_send "("
if qa_expect_screen "()" 5 -F; then
    qa_pass "( auto-closed with )"
else
    qa_fail "( auto-closed with )"
fi

# Type opening brace
qa_keys "end"
qa_keys "enter"
qa_send "{"
if qa_expect_screen "{}" 5 -F; then
    qa_pass "{ auto-closed with }"
else
    qa_fail "{ auto-closed with }"
fi

# Type opening square bracket
qa_keys "end"
qa_keys "enter"
qa_send "["
if qa_expect_screen "[]" 5 -F; then
    qa_pass "[ auto-closed with ]"
else
    qa_fail "[ auto-closed with ]"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
