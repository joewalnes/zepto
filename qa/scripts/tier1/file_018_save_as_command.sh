#!/usr/bin/env bash
# QA-FILE-018: "Save As" command in palette re-saves an already-titled file
#
# Distinct from QA-FILE-002 (⌃S on an UNTITLED file, which only prompts
# because there's no path yet). This exercises the new standalone
# "Save As" palette command (bugs.md P3 "No Save As command in palette"),
# which always prompts — even when the document already has a path.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-018: Save As command (palette)"

file=$(qa_tmpfile_nl "file018_orig.txt" "hello from save as")
qa_start "$file"

# Palette shows the command (discoverability)
qa_keys "ctrl-space"
qa_send "Save As" 0.3
qa_assert_expect "Save As" "palette lists 'Save As' command"

qa_keys "enter"
qa_assert_expect "Save As:" "footer input opens with 'Save As:' prompt"

# Prefilled with the current path, pre-selected — typing replaces it
newpath="$QA_TMPDIR/file018_new.txt"
qa_send "$newpath"
qa_keys "enter"

qa_assert_file_exists "$newpath" "file written at the new path"
qa_assert_file_contains "$newpath" "hello from save as" "new file has document's content"

# Original file must be untouched — this is Save As, not a rename
qa_assert_file_contains "$file" "hello from save as" "original file still has its content"
if [[ -e "$newpath" && -e "$file" ]]; then
    qa_pass "both old and new files exist on disk (copy, not move)"
else
    qa_fail "both old and new files exist on disk (copy, not move)"
fi

# Tab title updates to the new filename
qa_assert_expect "file018_new" "tab title shows new filename"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
