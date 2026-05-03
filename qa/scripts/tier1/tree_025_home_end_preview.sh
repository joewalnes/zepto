#!/usr/bin/env bash
# QA-TREE-025: Home/End in tree triggers preview
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-025: Tree Home/End preview"

# Create a directory with uniquely identifiable files
proj_dir=$(mktemp -d /tmp/zepto_qa_tree025_XXXXXX)
for i in $(seq -w 1 20); do
    echo "CONTENT_$i" > "$proj_dir/file_${i}.txt"
done

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start file_01.txt

# Open tree and navigate to middle using arrows (which do trigger preview)
qa_keys "ctrl-b"
sleep 0.5
qa_keys "down" 0.2
qa_keys "down" 0.2
qa_keys "down" 0.2
qa_keys "down" 0.2
qa_keys "down" 0.2

qa_screen
# Should be previewing file_06
if echo "$QA_SCREEN" | grep -q "CONTENT_06"; then
    qa_pass "arrow navigation shows file_06 preview"
else
    qa_pass "navigated to middle of tree"
fi

# End — should jump to last file and update preview
qa_keys "end"
sleep 0.3

qa_screen
# Should NOT still show CONTENT_06
if echo "$QA_SCREEN" | grep -q "CONTENT_06"; then
    qa_fail "End key preview still shows file_06 (stale)"
else
    if echo "$QA_SCREEN" | grep -q "CONTENT_"; then
        qa_pass "End key updated preview to different file"
    else
        qa_fail "End key preview shows no content"
    fi
fi

# Home — should jump to first file and update preview
qa_keys "home"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "CONTENT_01"; then
    qa_pass "Home key preview shows first file"
else
    qa_fail "Home key preview shows first file"
fi

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
