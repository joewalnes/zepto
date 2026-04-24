#!/usr/bin/env bash
# QA-TREE-025: Home/End in tree triggers preview
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-025: Tree Home/End preview"

# Create a directory with files
proj_dir=$(mktemp -d /tmp/zepto_qa_tree025_XXXXXX)
for i in $(seq -w 1 20); do
    echo "content of file $i" > "$proj_dir/file_${i}.txt"
done

qa_start "$proj_dir/file_01.txt"

# Open tree and navigate to middle
qa_keys "ctrl-b"
sleep 0.5
qa_keys "down" 0.2
qa_keys "down" 0.2
qa_keys "down" 0.2
qa_keys "down" 0.2
qa_keys "down" 0.2

qa_screen
mid_screen="$QA_SCREEN"

# Home — should jump to first entry and update preview
qa_keys "home"
sleep 0.3

qa_screen
home_screen="$QA_SCREEN"

if [[ "$mid_screen" != "$home_screen" ]]; then
    qa_pass "Home changed preview"
else
    qa_fail "Home changed preview"
fi

# End — should jump to last entry
qa_keys "end"
sleep 0.3

qa_screen
end_screen="$QA_SCREEN"

if [[ "$home_screen" != "$end_screen" ]]; then
    qa_pass "End changed preview"
else
    qa_fail "End changed preview"
fi

qa_keys "escape"
qa_keys "ctrl-q"

rm -rf "$proj_dir"
qa_summary
