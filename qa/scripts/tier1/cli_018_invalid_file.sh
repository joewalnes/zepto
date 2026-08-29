#!/usr/bin/env bash
# QA-CLI-018: Opening nonexistent file creates new buffer
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-018: Open nonexistent file"

nonexistent="$QA_TMPDIR/does_not_exist.txt"
qa_start "$nonexistent"

# Editor should open with empty buffer for new file
qa_assert_expect "does_not_exist|1:1" "editor opened with nonexistent file path"

# Should be able to type
qa_send "hello new file"
qa_assert_expect "hello new file" "can type in new file buffer"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2
qa_summary
