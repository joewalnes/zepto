#!/usr/bin/env bash
# QA-FIND-003: Find jumps to first match when off-screen (P1 REGRESSION)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-003: Find jumps to off-screen match (P1 regression)"

# Create a file with match only at line 50
content=""
for i in $(seq 1 49); do
    content+="line $i nothing special here
"
done
content+="line 50 FINDME here
"
for i in $(seq 51 60); do
    content+="line $i more text
"
done

file=$(qa_tmpfile "find003.txt" "$content")
qa_start "$file"

# We're at line 1 — FINDME is at line 50 (off-screen)
qa_keys "ctrl-f"
qa_send "FINDME"
sleep 0.5

# Viewport should have jumped to show "FINDME"
qa_assert_screen "FINDME" "viewport scrolled to show match"
qa_assert_screen "50" "line 50 visible in gutter or content"

qa_keys "escape"
qa_keys "ctrl-q"

qa_summary
