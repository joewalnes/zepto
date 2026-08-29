#!/usr/bin/env bash
# QA-FIND-019: Find works in word wrap mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-019: Find + word wrap"

long_line=$(python3 -c "print('before NEEDLE after ' * 10)")
file=$(qa_tmpfile_nl "find019.txt" "$long_line")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Search
qa_keys "ctrl-f"
qa_send "NEEDLE" 0.3

qa_wait_screen '[0-9]+ of [0-9]+' || true
count=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)
if [[ -n "$count" ]]; then
    qa_pass "find works in wrap mode ($count)"
else
    qa_fail "find works in wrap mode"
fi

qa_keys "escape"
qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
