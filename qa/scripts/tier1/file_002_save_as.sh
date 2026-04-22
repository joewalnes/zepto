#!/usr/bin/env bash
# QA-FILE-002: Save As on untitled file prompts for name
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-002: Save As on new untitled file"

qa_start  # no file arg = untitled

# Type some content
qa_send "test content 123"

# Save — should trigger Save As prompt since untitled
qa_keys "ctrl-s"
sleep 0.3

# Should see Save As prompt or footer input
qa_assert_screen "Save|save|name|path" "save-as prompt visible"

# Type a filename
savepath="$QA_TMPDIR/saved_file.txt"
qa_send "$savepath"
qa_keys "enter"
sleep 0.5

# File should exist on disk
qa_assert_file_exists "$savepath" "file created on disk"
qa_assert_file_contains "$savepath" "test content 123" "file contains typed content"

# Tab should show filename now
qa_assert_screen "saved_file" "tab title shows filename"

qa_keys "ctrl-q"

qa_summary
