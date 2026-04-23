#!/usr/bin/env bash
# QA-BIN-001: Binary file shows placeholder
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-BIN-001: Binary file detection"

# Create a binary file
binfile="$QA_TMPDIR/bin001.dat"
printf '\x00\x01\x02\x89PNG\r\n' > "$binfile"

qa_start "$binfile"

qa_assert_screen "Binary|binary|bytes" "binary file indicator shown"

qa_keys "ctrl-q"
qa_summary
