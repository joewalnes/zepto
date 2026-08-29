#!/usr/bin/env bash
# QA-SEC-009: Binary file content never executed
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-009: Binary content not executed"

# Create a binary file that contains shell-like content
binfile="$QA_TMPDIR/sec009.bin"
printf '\x00\x01#!/bin/sh\ntouch /tmp/zqa_exec_test\n\x00' > "$binfile"

rm -f /tmp/zqa_exec_test

qa_start "$binfile"
sleep 0.5

# Should show binary placeholder
qa_assert_expect "Binary file|binary file|READ ONLY" "binary placeholder shown"

# Verify no execution
if [[ -f /tmp/zqa_exec_test ]]; then
    qa_fail "binary content not executed" "/tmp/zqa_exec_test was created!"
    rm -f /tmp/zqa_exec_test
else
    qa_pass "binary content not executed"
fi

qa_keys "ctrl-q"
qa_summary
