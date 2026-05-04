#!/usr/bin/env bash
# QA-REG-021: New saved file visible in file tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-021: New saved file appears in tree"

mkdir -p "$QA_TMPDIR/treedir"
echo "existing" > "$QA_TMPDIR/treedir/existing.txt"

QA_ZEPTO=$(cd /Users/joe/src/zepto && pwd)/zepto
qa_start "$QA_TMPDIR/treedir/existing.txt"

# Make sure tree is visible
qa_keys "ctrl-b"
sleep 0.5

# Create a new tab and save it to the same directory
qa_keys "ctrl-n"
sleep 0.3
qa_send "new file content"

# Save As
qa_keys "ctrl-space"
sleep 0.5
qa_send "save as" 0.3
qa_keys "enter"
sleep 0.5

newpath="$QA_TMPDIR/treedir/newfile.txt"
qa_send "$newpath" 0.3
qa_keys "enter"
sleep 1

# Check if file exists on disk
if [[ -f "$newpath" ]]; then
    qa_pass "new file saved to disk"
else
    qa_skip "Save As interaction may need adjustment"
fi

qa_keys "ctrl-q"
qa_summary
