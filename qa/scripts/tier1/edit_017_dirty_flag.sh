#!/usr/bin/env bash
# QA-EDIT-017+018: Dirty flag appears on edit, clears on save
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-017: Dirty flag"

file=$(qa_tmpfile_nl "edit017.txt" "clean file")
qa_start "$file"

# Should be clean initially
qa_assert_not_screen "●" "no dirty indicator initially"

# Make an edit
qa_send "x"
qa_assert_screen "●" "dirty indicator after edit"

# Save
qa_keys "ctrl-s"
qa_assert_not_screen "●" "dirty indicator gone after save"

qa_keys "ctrl-q"
qa_summary
