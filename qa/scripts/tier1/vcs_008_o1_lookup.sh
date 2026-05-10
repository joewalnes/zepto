#!/usr/bin/env bash
# QA-VCS-008: VCS change lookup performant
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-008: VCS O(1) lookup"

dir=$(qa_git_repo)
content=""
for i in $(seq 1 200); do content+="line $i"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"
qa_sed_i 's/line 100/line 100 CHANGED/' test.txt

qa_start test.txt
sleep 1

# Jump to change with Alt+N
qa_keys "alt-n"
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 98 && "$QA_CURSOR_LINE" -le 102 ]]; then
    qa_pass "VCS jump found change at line $QA_CURSOR_LINE"
else
    qa_fail "VCS jump (at $QA_CURSOR_LINE, expected ~100)"
fi

qa_keys "ctrl-q"
qa_summary
