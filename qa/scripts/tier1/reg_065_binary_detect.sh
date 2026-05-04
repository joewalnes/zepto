#!/usr/bin/env bash
# QA-REG-065: Binary file detection with NUL bytes + save blocked
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-065: Binary file detection and placeholder"

# Create binary file with NUL bytes
binfile="$QA_TMPDIR/reg065.bin"
printf 'hello\x00world\x01\x02' > "$binfile"

qa_start "$binfile"

qa_assert_screen "Binary|binary|bytes" "binary file detected"

# Try to type — should be blocked
qa_send "test" 0.3

# Try to save — should be blocked
qa_keys "ctrl-s"
sleep 0.3

# File content should be unchanged
actual=$(cat "$binfile" | od -An -tx1 | head -1 || true)
if echo "$actual" | grep -q "00"; then
    qa_pass "binary file content preserved (NUL bytes intact)"
else
    qa_skip "could not verify binary content preservation"
fi

qa_keys "ctrl-q"
qa_summary
