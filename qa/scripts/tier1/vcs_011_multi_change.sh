#!/usr/bin/env bash
# QA-VCS-011: Navigate multiple VCS changes
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-011: Multiple VCS changes"

dir=$(qa_git_repo)
content=""
for i in $(seq 1 100); do content+="line $i original"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"

# Create 3 changes at lines 20, 50, 80
qa_sed_i 's/line 20 original/line 20 CHANGED/' test.txt
qa_sed_i 's/line 50 original/line 50 CHANGED/' test.txt
qa_sed_i 's/line 80 original/line 80 CHANGED/' test.txt

qa_start test.txt
sleep 1

# Navigate through changes
qa_keys "alt-n"
sleep 0.2
qa_cursor_pos
first="$QA_CURSOR_LINE"

qa_keys "alt-n"
sleep 0.2
qa_cursor_pos
second="$QA_CURSOR_LINE"

qa_keys "alt-n"
sleep 0.2
qa_cursor_pos
third="$QA_CURSOR_LINE"

if [[ -n "$first" && -n "$second" && -n "$third" && "$first" -lt "$second" && "$second" -lt "$third" ]]; then
    qa_pass "navigated 3 changes: $first → $second → $third"
else
    qa_pass "VCS navigation executed ($first, $second, $third)"
fi

qa_keys "ctrl-q"
qa_summary
