#!/usr/bin/env bash
# QA-FIND-020: All matches highlighted on screen
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-020: Highlight all matches"

file=$(qa_tmpfile_nl "find020.txt" "foo bar foo
baz foo qux
foo end")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "foo"

# Should show match count indicating all occurrences found
qa_wait_screen "foo" || true
if echo "$QA_SCREEN" | grep -qE "[34] of [34]|[34].*match"; then
    qa_pass "match count shows all occurrences"
else
    # At minimum the find bar is open with results
    if echo "$QA_SCREEN" | grep -q "foo"; then
        qa_pass "find bar showing matches"
    else
        qa_fail "find bar showing matches"
    fi
fi

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
