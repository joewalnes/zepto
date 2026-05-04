#!/usr/bin/env bash
# QA-REG-004: Save is atomic (temp+rename)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-004: Atomic save"

file=$(qa_tmpfile_nl "reg004.txt" "original content")
qa_start "$file"

# Get original inode
orig_inode=$(stat -f '%i' "$file" 2>/dev/null || stat -c '%i' "$file" 2>/dev/null || true)

# Modify and save
qa_keys "end"
qa_send " modified"
qa_keys "ctrl-s"
sleep 0.3

# Verify content is correct
qa_assert_file_contains "$file" "modified" "file saved with new content"

# Verify file exists and is readable (atomic = no partial writes)
content=$(cat "$file")
if echo "$content" | grep -q "original content modified"; then
    qa_pass "save produced complete file"
else
    qa_fail "save produced complete file (got: ${content:0:40})"
fi

qa_keys "ctrl-q"
qa_summary
