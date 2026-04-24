#!/usr/bin/env bash
# QA-MS-019: Scroll wheel in file tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-019: Mouse scroll in tree"

# Create a directory with many files
proj_dir=$(mktemp -d /tmp/zepto_qa_ms019_XXXXXX)
for i in $(seq -w 1 50); do
    echo "content $i" > "$proj_dir/file_${i}.txt"
done

qa_start "$proj_dir/file_01.txt"

# Open tree
qa_keys "ctrl-b"
sleep 0.5

qa_screen
before="$QA_SCREEN"

# Scroll down in the tree area (left side, col 10)
hangon mouse-scroll "$QA_SESSION" --x 10 --y 10 --delta 5
sleep 0.3

qa_screen
after="$QA_SCREEN"

if [[ "$before" != "$after" ]]; then
    qa_pass "scroll wheel scrolled tree"
else
    qa_fail "scroll wheel scrolled tree"
fi

qa_keys "escape"
qa_keys "ctrl-q"

rm -rf "$proj_dir"
qa_summary
