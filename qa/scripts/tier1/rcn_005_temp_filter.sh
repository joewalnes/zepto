#!/usr/bin/env bash
# QA-RCN-005: Temp files filtered from recent list
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-005: Temp files filtered from recents"

# Create a temp file and a real file
tmpfile="/tmp/zepto_qa_rcn005_throwaway.txt"
echo "throwaway" > "$tmpfile"
realfile=$(qa_tmpfile_nl "rcn005_real.txt" "real content")

# Session 1: open the temp file
qa_start "$tmpfile"
qa_keys "ctrl-q"

# Session 2: open the real file and check recents
qa_restart "$realfile"
qa_keys "ctrl-e" 0.5

qa_screen
# Temp file should NOT appear in recents
if echo "$QA_SCREEN" | grep -q "throwaway"; then
    qa_fail "temp file appeared in recent list"
else
    qa_pass "temp file filtered from recent list"
fi

qa_keys "escape"
qa_keys "ctrl-q"
rm -f "$tmpfile"
qa_summary
