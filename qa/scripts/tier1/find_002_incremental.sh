#!/usr/bin/env bash
# QA-FIND-002: Typing in find filters matches incrementally
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-002: Incremental find"

file=$(qa_tmpfile_nl "find002.txt" "apple banana cherry
apple pie
banana split")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "apple" 0.3

qa_assert_screen "2" "match count shows 2 matches for 'apple'"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
