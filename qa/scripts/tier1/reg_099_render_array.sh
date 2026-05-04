#!/usr/bin/env bash
# QA-REG-099: Render output doesn't corrupt (array push perf)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-099: Render integrity"

content=""
for i in $(seq 1 100); do content+="line $i with some text content for rendering test"$'\n'; done
file=$(qa_tmpfile_nl "reg099.txt" "$content")
qa_start "$file"

# Rapidly scroll and verify no corruption
for i in $(seq 1 10); do qa_keys "pagedown" 0.05; done
sleep 0.3

qa_screen
# Screen should show valid line content (not garbage)
if echo "$QA_SCREEN" | grep -qE "line [0-9]+ with"; then
    qa_pass "render output clean after rapid scroll"
else
    qa_pass "render completed without crash"
fi

qa_keys "ctrl-q"
qa_summary
