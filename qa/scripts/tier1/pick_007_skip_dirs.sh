#!/usr/bin/env bash
# QA-PICK-007: Skip directories excluded from discovery
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-007: Picker skips noise directories"

dir=$(qa_git_repo)
echo "real file" > real.txt
mkdir -p node_modules
echo "noise" > node_modules/noise.js
mkdir -p .venv
echo "noise" > .venv/noise.py
git add real.txt && git commit -q -m "init"

qa_start real.txt

qa_keys "ctrl-p" 0.5
qa_send "noise" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qE "node_modules|\.venv"; then
    qa_fail "picker shows files from skip directories"
else
    qa_pass "picker excludes skip directories"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
