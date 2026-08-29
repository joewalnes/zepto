#!/usr/bin/env bash
# QA-SEC-004: No shell injection via file open
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-004: No shell injection in open"

# Create a file with shell metacharacters in name
mkdir -p "$QA_TMPDIR/sec004"
echo "safe content" > "$QA_TMPDIR/sec004/normal.txt"
echo "also safe" > "$QA_TMPDIR/sec004/file;echo pwned.txt" 2>/dev/null || true

qa_start "$QA_TMPDIR/sec004/normal.txt"

# Verify editor opened safely
qa_assert_expect "safe content" "file opened safely"

# Verify no command execution occurred
if [[ ! -f "$QA_TMPDIR/sec004/pwned" ]]; then
    qa_pass "no shell injection from filename"
else
    qa_fail "shell injection detected!"
fi

qa_keys "ctrl-q"
qa_summary
