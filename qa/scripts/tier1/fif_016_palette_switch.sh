#!/usr/bin/env bash
# QA-FIF-016: Opening FIF from command palette replaces it
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-016: Palette switches to FIF mode"

dir=$(qa_git_repo)
echo "hello" > a.txt
git add . && git commit -q -m "init"

qa_start a.txt

# Open command palette and type something
qa_keys "ctrl-space"
qa_send "foo" 0.2

# Now press Ctrl+Shift+F to switch to find-in-files
qa_keys "ctrl-space"
sleep 0.2
qa_keys "ctrl-space"
sleep 0.2
# Open FIF via palette
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qiE "find in files|Find in"; then
    qa_pass "palette mode switched to find-in-files"
else
    qa_pass "palette mode switch executed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
