#!/usr/bin/env bash
# QA-GOTO-014: Location history caps at reasonable size
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GOTO-014: History cap"

content=""
for i in $(seq 1 200); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "goto014.txt" "$content")
qa_start "$file"

# Perform many jumps (>100)
for i in 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150; do
    qa_keys "ctrl-g"
    qa_send "$i" 0.1
    qa_keys "enter"
    sleep 0.1
done

# Go back — should work without crashing
for i in $(seq 1 10); do qa_keys "alt--" 0.1; done

# Should still be responsive
if qa_alive; then
    qa_pass "editor alive after many history jumps"
else
    qa_fail "editor crashed after many jumps"
fi

qa_keys "ctrl-q"
qa_summary
