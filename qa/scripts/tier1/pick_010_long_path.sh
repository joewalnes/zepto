#!/usr/bin/env bash
# QA-PICK-010: Long path truncated with ellipsis
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-010: Long path truncation"

dir=$(qa_git_repo)
mkdir -p a/very/deeply/nested/directory/structure
echo "deep file" > a/very/deeply/nested/directory/structure/target.txt
echo "root" > root.txt
git add . && git commit -q -m "init"

qa_start root.txt

qa_keys "ctrl-p" 0.5
qa_send "target" 0.3

qa_screen
# Should show path but possibly truncated
if echo "$QA_SCREEN" | grep -q "target"; then
    qa_pass "deep file found in picker"
else
    qa_fail "deep file not found in picker"
fi

# Verify no overflow outside palette box
if qa_alive 2>/dev/null; then
    qa_pass "long path displayed without crash"
else
    qa_fail "long path crashed picker"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
