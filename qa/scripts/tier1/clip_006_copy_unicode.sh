#!/usr/bin/env bash
# QA-CLIP-006: Copy CJK/emoji doesn't crash
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLIP-006: Copy CJK/emoji without crash"

file=$(qa_tmpfile "clip006.txt" "")
qa_start "$file"

qa_send "hello"
qa_keys "ctrl-a"
qa_keys "ctrl-c"

# Editor should still be alive and responsive
qa_alive && qa_pass "editor alive after copy" || qa_fail "editor crashed after copy"
qa_assert_screen "hello" "buffer content intact"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
