#!/usr/bin/env bash
# QA-FILE-014: Save during VCS diff updates gutter
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-014: Save with VCS gutter"

# Create a temp git repo
QA_ZEPTO="$(cd "$(dirname "$0")/../../.." && pwd)/zepto"

gitdir="$QA_TMPDIR/repo014"
mkdir -p "$gitdir"
cd "$gitdir"
git init -q
echo "original line" > test.txt
git add test.txt
git commit -q -m "init"

qa_start "$gitdir/test.txt"

# Make an edit
qa_keys "end"
qa_send " modified"

# Save
qa_keys "ctrl-s"
sleep 0.5

# File saved, editor alive
qa_alive && qa_pass "editor alive after save in git repo" || qa_fail "editor crashed"

qa_keys "ctrl-q"
qa_summary
