#!/usr/bin/env bash
# QA-BIN-003: Save blocked for binary file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-BIN-003: Save blocked for binary file"

binfile="$QA_TMPDIR/bin003.dat"
printf '\x00\x01\x02\x03binary content\x00' > "$binfile"
# Save original for comparison
cp "$binfile" "$binfile.orig"

qa_start "$binfile"
sleep 0.3

# Try to save
qa_keys "ctrl-s"
sleep 0.3

# Should show error or "cannot save"
qa_screen
if echo "$QA_SCREEN" | grep -qiE "cannot|read.only|binary|blocked|error"; then
    qa_pass "save blocked with appropriate message"
else
    # Verify file not modified
    if cmp -s "$binfile" "$binfile.orig"; then
        qa_pass "save blocked (file unchanged)"
    else
        qa_fail "save blocked for binary file" "file was modified"
    fi
fi

qa_keys "ctrl-q"
qa_summary
