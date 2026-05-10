#!/usr/bin/env bash
# QA-RCN-006: Non-existent files gracefully handled in recent list
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-006: Non-existent file in recents"

# Create a file, open it, then delete it
tmpfile="$QA_TMPDIR/rcn006_ephemeral.txt"
echo "ephemeral" > "$tmpfile"

qa_start "$tmpfile"
qa_keys "ctrl-q"
sleep 0.3

# Delete the file
rm -f "$tmpfile"

# Relaunch and check recents
qa_restart "$QA_TMPDIR/dummy.txt"
sleep 0.3
# Create the dummy so zepto can open
echo "dummy" > "$QA_TMPDIR/dummy.txt"
qa_stop
qa_start "$QA_TMPDIR/dummy.txt"

qa_keys "ctrl-e" 0.5

# No crash when listing deleted file
if qa_alive 2>/dev/null; then
    qa_pass "recent list handles non-existent file gracefully"
else
    qa_fail "recent list crashed on non-existent file"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
