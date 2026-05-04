#!/usr/bin/env bash
# QA-FIND-025: Home/End navigation in find input field
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-025: Home/End in find input"

file=$(qa_tmpfile_nl "find025.txt" "abcdefghij klmnop
abcdefghij second")
qa_start "$file"

# Open find and type a query
qa_keys "ctrl-f"
qa_send "abcdefghij" 0.3

# Press Home to go to start of input, then type a prefix
qa_keys "home" 0.2
qa_send "X" 0.3

# The find input should now contain "Xabcdefghij"
# It should NOT match "abcdefghij" anymore
qa_assert_not_screen "1 of 2|2 of 2" "Home moved cursor to start of input, no match for prefixed query"

# Press End, then type suffix
qa_keys "end" 0.2
qa_send "Y" 0.3

# Query is now "XabcdefghijY" - no match expected
qa_screen
match_info=$(echo "$QA_SCREEN" | grep -oE '[0-9]+ of [0-9]+' | head -1 || true)
if [[ -z "$match_info" || "$match_info" == "0 of 0" ]]; then
    qa_pass "End moved cursor to end of input"
else
    qa_fail "End moved cursor to end of input" "unexpected match: $match_info"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
