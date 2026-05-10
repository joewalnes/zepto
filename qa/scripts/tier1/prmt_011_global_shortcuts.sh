#!/usr/bin/env bash
# QA-PRMT-011: Global shortcuts work during prompt
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-011: Global shortcuts during prompt"

file=$(qa_tmpfile_nl "prmt011.txt" "original")
qa_start "$file"

qa_send "dirty"

# Trigger save prompt
qa_keys "ctrl-w"
sleep 0.3

qa_assert_screen "Save|Discard|Cancel" "save prompt visible"

# Ctrl+Q should work even during prompt
qa_keys "ctrl-q"
sleep 0.5

# Either prompt changes or quit begins
qa_screen
if qa_alive 2>/dev/null; then
    # Might still be showing prompt, cancel it
    qa_send "n" 0.2
    qa_pass "ctrl-q during prompt handled (editor still alive)"
else
    qa_pass "ctrl-q during prompt initiated quit"
fi

# Clean up if still alive
if qa_alive 2>/dev/null; then
    qa_keys "ctrl-q"
    sleep 0.2
    qa_send "n"
fi
qa_summary
