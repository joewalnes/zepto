#!/usr/bin/env bash
# QA-UNDO-012: Undo restores dirty flag
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-UNDO-012: Undo restores clean state"

file=$(qa_tmpfile_nl "undo012.txt" "saved content")
qa_start "$file"

qa_assert_not_screen "●" "clean initially"

qa_send "x"
qa_assert_expect "●" "dirty after edit"

qa_keys "ctrl-z"
qa_assert_not_screen "●" "clean after undo"

qa_keys "ctrl-q"
qa_summary
