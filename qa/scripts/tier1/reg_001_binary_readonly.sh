#!/usr/bin/env bash
# QA-REG-001: Binary file shows placeholder, not raw content
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-001: Binary file placeholder"

# Create a binary file with NUL bytes
binfile="$QA_TMPDIR/reg001.dat"
printf '\x00\x01\x02\x89PNG\r\n' > "$binfile"

qa_start "$binfile"

qa_assert_screen "Binary file|binary file" "binary file placeholder shown"

qa_keys "ctrl-q"
qa_summary
