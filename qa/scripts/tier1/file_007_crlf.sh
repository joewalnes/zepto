#!/usr/bin/env bash
# QA-FILE-007: Save preserves CRLF line endings
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-007: Save preserves CRLF endings"

# Create file with CRLF endings
file="$QA_TMPDIR/file007.txt"
printf "line one\r\nline two\r\nline three\r\n" > "$file"

qa_start "$file"

# Edit and save
qa_keys "end"
qa_send " edited"
qa_keys "ctrl-s"
sleep 0.3

# Check file on disk still has CRLF
if od -c "$file" | grep -q '\\r'; then
    qa_pass "file preserved CRLF endings"
else
    qa_fail "file lost CRLF endings"
fi

qa_keys "ctrl-q"
qa_summary
