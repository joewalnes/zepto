#!/usr/bin/env bash
# QA-CMT-002: Toggle comment uncomments commented line
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CMT-002: Uncomment"

file=$(qa_tmpfile_nl "cmt002.py" "# already commented
normal line")
qa_start "$file"

# Toggle comment on already-commented line should uncomment it (Ctrl+/ = 0x1f)
qa_raw $'\x1f'

# Save and check
qa_keys "ctrl-s"
sleep 0.3

line1=$(head -1 "$file")
if [[ "$line1" == "already commented" || "$line1" == " already commented" ]]; then
    qa_pass "toggle comment uncommented the line"
else
    qa_fail "toggle comment uncommented the line (got: $line1)"
fi

qa_keys "ctrl-q"
qa_summary
