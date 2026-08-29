#!/usr/bin/env bash
# QA-FILE-019 / QA-REG-127: "Save As" command prompts before overwriting
# a different existing file, and does NOT prompt when re-saving to its
# own current path.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-019: Save As overwrite confirmation"

current=$(qa_tmpfile_nl "file019_current.txt" "current content")
other=$(qa_tmpfile_nl "file019_other.txt" "other content")
qa_start "$current"

# --- Choosing "No" cancels: other.txt is untouched ---
qa_keys "ctrl-space"
qa_send "Save As" 0.3
qa_keys "enter"
qa_send "$other"
qa_keys "enter"
qa_assert_expect "already exists. Overwrite?" "overwrite prompt appears for a different existing file"

qa_send "n"
qa_assert_file_contains "$other" "other content" "'No' leaves the other file's content untouched"
qa_assert_expect "file019_current" "'No' leaves the tab on the original file"

# --- Choosing "Yes" overwrites ---
qa_keys "ctrl-space"
qa_send "Save As" 0.3
qa_keys "enter"
qa_send "$other"
qa_keys "enter"
qa_assert_expect "already exists. Overwrite?" "overwrite prompt appears again"

qa_send "y"
qa_assert_file_contains "$other" "current content" "'Yes' overwrites the other file with this document's content"
qa_assert_expect "file019_other" "tab title updates to the overwritten file"

# --- Re-saving to the document's OWN current path does not prompt ---
qa_keys "ctrl-space"
qa_send "Save As" 0.3
qa_keys "enter"
# Footer input is prefilled with the current path (now file019_other.txt)
# and pre-selected; submit without retyping to save to the same path.
qa_keys "enter"
qa_screen
if echo "$QA_SCREEN" | grep -q "Overwrite?"; then
    qa_fail "re-saving to the document's own path does not prompt" "unexpected overwrite prompt"
else
    qa_pass "re-saving to the document's own path does not prompt"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
