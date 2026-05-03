#!/usr/bin/env bash
# QA-MS-019: Scroll wheel in file tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-019: Mouse scroll in tree"

# Create a directory with many sequentially-named files
proj_dir=$(mktemp -d /tmp/zepto_qa_ms019_XXXXXX)
for i in $(seq -w 1 50); do
    echo "content $i" > "$proj_dir/file_${i}.txt"
done

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start file_01.txt

# Open tree
qa_keys "ctrl-b"
sleep 0.5

# file_01 should be visible at top of tree
qa_assert_screen "file_01" "file_01 visible in tree"

# Scroll down in the tree area (left side, col 10)
hangon mouse-scroll "$QA_SESSION" --x 10 --y 10 --delta 10
sleep 0.3

# After scrolling, higher-numbered files should be visible
# and file_01 might be scrolled off
qa_screen
if echo "$QA_SCREEN" | grep -qE "file_(1[5-9]|2[0-9]|3[0-9])"; then
    qa_pass "scroll revealed higher-numbered files"
else
    qa_fail "scroll revealed higher-numbered files"
fi

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
