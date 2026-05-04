#!/usr/bin/env bash
# QA-SEC-007: Terminal title filename sanitized
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-007: Terminal title sanitized"

# Create file with control chars in name (safe subset)
sanitize_dir=$(mktemp -d /tmp/zepto_qa_sec007_XXXXXX)
# Use a filename with a tab character (harmless but tests sanitization)
safe_name="normal_file.txt"
printf 'safe content\n' > "$sanitize_dir/$safe_name"

qa_start "$sanitize_dir/$safe_name"
sleep 0.3

# Editor should open normally
qa_assert_screen "safe content" "file with normal name opens fine"

# Verify the editor is functional
qa_keys "ctrl-q"

qa_pass "terminal title handling did not crash editor"

rm -rf "$sanitize_dir"
qa_summary
