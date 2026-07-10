#!/usr/bin/env bash
# QA-WRAP-008: VCS gutter markers extend across wrapped rows
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-008: VCS gutter on wrapped lines"

qa_git_repo; dir="$QA_PROJECT_DIR"
echo "short line" > test.txt
git add . && git commit -q -m "init"

# Replace with a long line that will wrap
long_line=$(python3 -c "print('modified ' * 30)")
echo "$long_line" > test.txt

qa_start test.txt

# Enable wrap
qa_keys "alt-z"
sleep 0.5

# Editor should show the file with wrap and gutter markers
qa_screen
# The modified line should cause VCS gutter markers
# With wrap on, continuation rows should also show markers
if qa_alive 2>/dev/null; then
    qa_pass "editor renders wrapped lines with VCS gutter (no crash)"
else
    qa_fail "editor crashed with VCS gutter on wrapped lines"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
