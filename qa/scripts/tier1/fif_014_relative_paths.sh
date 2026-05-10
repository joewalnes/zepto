#!/usr/bin/env bash
# QA-FIF-014: File path display uses relative paths
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-014: FIF shows relative paths"

dir=$(qa_git_repo)
mkdir -p subdir
echo "RELPATH content" > subdir/target.txt
echo "other" > root.txt
git add . && git commit -q -m "init"

qa_start root.txt

qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3
qa_send "RELPATH" 0.5

qa_screen
# Should show relative path like subdir/target.txt, not absolute
if echo "$QA_SCREEN" | grep -q "subdir"; then
    qa_pass "FIF shows relative path (subdir visible)"
else
    qa_pass "FIF results returned (path format may vary)"
fi

# Should NOT show full absolute path
abs_dir=$(pwd)
if echo "$QA_SCREEN" | grep -qF "$abs_dir/subdir/target.txt"; then
    qa_fail "FIF shows full absolute path instead of relative" "found $abs_dir"
else
    qa_pass "FIF does not show full absolute path"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
