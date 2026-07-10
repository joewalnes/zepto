#!/usr/bin/env bash
# QA-VCS-007: Adaptive debounce on large VCS files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-007: VCS debounce"

qa_git_repo; dir="$QA_PROJECT_DIR"
content=""
for i in $(seq 1 500); do content+="line $i original"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"
qa_sed_i 's/line 250 original/line 250 MODIFIED/' test.txt

qa_start test.txt
sleep 1

# Rapid typing shouldn't freeze editor
for i in $(seq 1 10); do qa_send "x" 0.05; done
sleep 0.5

if qa_alive; then
    qa_pass "editor responsive during rapid edits on VCS file"
else
    qa_fail "editor responsive during rapid edits"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
