#!/usr/bin/env bash
# QA-FILE-006: Save preserves LF line endings
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-006: Save preserves LF endings"

file=$(qa_tmpfile_nl "file006.txt" "line one
line two
line three")
qa_start "$file"

# Edit and save
qa_keys "end"
qa_send " edited"
qa_keys "ctrl-s"
sleep 0.3

# Check file on disk for LF endings (no \r)
if od -c "$file" | grep -q '\\r'; then
    qa_fail "file has LF-only endings (found CR)"
else
    qa_pass "file has LF-only endings"
fi

qa_keys "ctrl-q"
qa_summary
