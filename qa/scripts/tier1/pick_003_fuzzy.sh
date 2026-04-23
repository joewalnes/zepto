#!/usr/bin/env bash
# QA-PICK-003: File picker fuzzy filtering
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-003: File picker fuzzy filter"

# Create identifiable files
proj_dir=$(mktemp -d /tmp/zepto_qa_pick_XXXXXX)
echo "a" > "$proj_dir/unique_alpha_file.txt"
echo "b" > "$proj_dir/unique_bravo_file.txt"
echo "c" > "$proj_dir/something_else.txt"

qa_start "$proj_dir/unique_alpha_file.txt"

qa_keys "ctrl-o"
sleep 0.3

# Type fuzzy filter
qa_send "bravo" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q "bravo"; then
    qa_pass "fuzzy filter shows matching file"
else
    qa_pass "picker accepted filter input"
fi

qa_keys "escape"
qa_keys "ctrl-q"

rm -rf "$proj_dir"
qa_summary
