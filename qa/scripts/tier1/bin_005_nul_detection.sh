#!/usr/bin/env bash
# QA-BIN-005: Binary detection uses first 8KB NUL scan
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-BIN-005: NUL byte detection in first 8KB"

# File with NUL byte early on
binfile="$QA_TMPDIR/bin005_early.dat"
printf 'text\x00more text\n' > "$binfile"

qa_start "$binfile"

qa_assert_expect "Binary file|binary file|READ ONLY" "NUL byte detected as binary"

qa_keys "ctrl-q"
qa_summary
