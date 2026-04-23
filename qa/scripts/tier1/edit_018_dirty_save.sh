#!/usr/bin/env bash
# QA-EDIT-018: Dirty flag cleared on save
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-018: Save clears dirty flag"

file=$(qa_tmpfile_nl "edit018.txt" "content")
qa_start "$file"

qa_send "x"
qa_assert_screen "●" "dirty after edit"

qa_keys "ctrl-s"
qa_assert_not_screen "●" "clean after save"
qa_assert_screen "Saved" "saved message shown"

qa_keys "ctrl-q"
qa_summary
