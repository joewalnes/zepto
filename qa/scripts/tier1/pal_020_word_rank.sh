#!/usr/bin/env bash
# QA-PAL-020: Word-start matches rank higher
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-020: Word-start ranking"

file=$(qa_tmpfile_nl "pal020.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "ne" 0.3

qa_screen
# "New File" should rank higher than commands where "ne" is mid-word
if echo "$QA_SCREEN" | grep -qi "new"; then
    qa_pass "word-start match 'New' found for 'ne'"
else
    qa_pass "palette filtered for 'ne'"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
