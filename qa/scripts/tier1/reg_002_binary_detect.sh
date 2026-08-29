#!/usr/bin/env bash
# QA-REG-002: Binary file detected by NUL scan
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-002: Binary NUL detection"

# Create file with NUL byte
binfile="$QA_TMPDIR/reg002.bin"
printf 'hello\x00world' > "$binfile"

qa_start "$binfile"

qa_assert_expect "Binary" "binary file detected"

qa_keys "ctrl-q"
qa_summary
