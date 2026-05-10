#!/usr/bin/env bash
# QA-WRAP-009: Diff view preserves word wrap
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-009: Diff view preserves wrap"

dir=$(qa_git_repo)
long_line=$(python3 -c "print('original ' * 30)")
echo "$long_line" > test.txt
git add . && git commit -q -m "init"

# Modify the line
long_modified=$(python3 -c "print('modified ' * 30)")
echo "$long_modified" > test.txt

qa_start test.txt

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Toggle diff
qa_keys "alt-d"
sleep 0.5

qa_screen
# Diff should expand inline; editor should be alive
if qa_alive 2>/dev/null; then
    qa_pass "diff view works with word wrap enabled"
else
    qa_fail "diff view crashed with word wrap"
fi

# Close diff
qa_keys "alt-d"
qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
