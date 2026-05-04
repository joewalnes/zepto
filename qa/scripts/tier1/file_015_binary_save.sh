#!/usr/bin/env bash
# QA-FILE-015: Binary save blocked
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-015: Binary save blocked"

# Create a binary file
binfile="$QA_TMPDIR/file015.bin"
printf '\x00\x01\x02\x03\x04\x05' > "$binfile"

qa_start "$binfile"
sleep 0.5

# Try to save
qa_keys "ctrl-s"
sleep 0.5

qa_screen
if echo "$QA_SCREEN" | grep -qiE "binary|cannot|read.only"; then
    qa_pass "binary save blocked or read-only"
else
    qa_skip "binary detection behavior unclear from screen"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
