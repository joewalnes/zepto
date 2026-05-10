#!/usr/bin/env bash
# QA-FIF-009: Find-in-files falls back to rg when not in git repo
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-009: FIF fallback outside git repo"

# Create a non-git directory
proj_dir=$(mktemp -d /tmp/zepto_qa_fif009_XXXXXX)
echo "SEARCHME in file1" > "$proj_dir/a.txt"
echo "nothing here" > "$proj_dir/b.txt"
echo "SEARCHME in file3" > "$proj_dir/c.txt"

cd "$proj_dir"
qa_start a.txt

# Open find-in-files
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

qa_send "SEARCHME" 0.5

qa_screen
if echo "$QA_SCREEN" | grep -qE "SEARCHME|match|result"; then
    qa_pass "find-in-files works outside git repo (fallback backend)"
else
    qa_fail "find-in-files works outside git repo"
fi

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
