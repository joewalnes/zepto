#!/usr/bin/env bash
# QA-EXT-006: File deleted externally while open
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EXT-006: File deleted externally"

file=$(qa_tmpfile_nl "ext006.txt" "important content")
qa_start "$file"

qa_assert_screen "important content" "file loaded"

# Delete the file externally
rm "$file"

# Interact
qa_keys "escape"
sleep 1.5

# Editor should not crash
qa_alive && qa_pass "editor alive after file deletion" || qa_fail "editor crashed"

# Content should still be in buffer
qa_assert_screen "important content" "buffer retained after file deletion"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
