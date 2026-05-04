#!/usr/bin/env bash
# QA-REG-003: Editor not sluggish on large file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-003: Large file performance"

content=""
for i in $(seq 1 5000); do content+="line $i with some content here for testing"$'\n'; done
file=$(qa_tmpfile_nl "reg003.txt" "$content")

start=$(date +%s)
qa_start "$file"
end=$(date +%s)
elapsed=$((end - start))

if [[ $elapsed -le 5 ]]; then
    qa_pass "5K line file opened in ${elapsed}s"
else
    qa_fail "5K line file opened in ${elapsed}s (expected <= 5s)"
fi

# Navigate to middle — should be responsive
qa_keys "ctrl-g"
qa_send "2500" 0.2
qa_keys "enter"
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 2498 ]]; then
    qa_pass "navigation responsive in large file (at $QA_CURSOR_LINE)"
else
    qa_fail "navigation responsive (at $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
qa_summary
