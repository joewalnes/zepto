#!/usr/bin/env bash
# QA-FILE-001: Save existing file writes changes to disk
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-001: Save existing file"

file=$(qa_tmpfile_nl "file001.txt" "original content")
qa_start "$file"

# Edit
qa_keys "end"
qa_send " modified"

# Save
qa_keys "ctrl-s"

# Check file on disk
qa_assert_file_contains "$file" "original content modified" "file on disk updated"

# Dirty indicator should be gone
qa_assert_screen "Saved" "saved message visible"

qa_keys "ctrl-q"
qa_summary
