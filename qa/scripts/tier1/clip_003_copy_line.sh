#!/usr/bin/env bash
# QA-CLIP-003: Copy with no selection copies entire line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-003: Copy line (no selection)"

file=$(qa_tmpfile_nl "clip003.txt" "first line
second line")
qa_start "$file"

# No selection — copy should grab entire line 1 ("first line")
qa_keys "ctrl-c"

# Move to end of file and paste. NOTE: "first line" is already visible on
# screen unconditionally (it's still line 1 of the file) — asserting for it
# alone would pass even if copy/paste were completely broken. Instead assert
# it now appears a SECOND time, appended after "second line", which can only
# happen if the copied line was actually pasted.
qa_keys "down" 0.1
qa_keys "end" 0.1
qa_keys "enter"
qa_keys "ctrl-v"

qa_screen
first_line_count=$(echo "$QA_SCREEN" | grep -c "first line" || true)
if [[ "$first_line_count" -ge 2 ]]; then
    qa_pass "pasted line duplicated 'first line' content ($first_line_count occurrences)"
else
    qa_fail "pasted line duplicated 'first line' content" "expected >=2 occurrences, got $first_line_count"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
