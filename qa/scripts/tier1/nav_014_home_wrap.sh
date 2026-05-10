#!/usr/bin/env bash
# QA-NAV-014: Home in word-wrap continuation row
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-014: Home in wrapped continuation row"

long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "nav014.txt" "$long_line")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Move down into continuation row
qa_keys "down" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1

# Press Home — should go to start of visual row
qa_keys "home"
sleep 0.2

# Editor should still be alive and cursor moved
if qa_alive 2>/dev/null; then
    qa_pass "home on continuation row works (no crash)"
else
    qa_fail "home on continuation row crashed"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
