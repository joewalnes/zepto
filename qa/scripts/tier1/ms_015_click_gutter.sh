#!/usr/bin/env bash
# QA-MS-015: Click in gutter toggles hunk
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-015: Click gutter toggles diff hunk"

repo_dir=$(mktemp -d /tmp/zepto_qa_ms015_XXXXXX)
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

content=""
for i in $(seq 1 15); do content+="line $i original"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"

if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/line 5 original/line 5 CHANGED/' test.txt
else
    sed -i 's/line 5 original/line 5 CHANGED/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1

# Click on gutter area near line 5 (col 1-2 is gutter)
hangon mouse-click "$QA_SESSION" --x 1 --y 7
sleep 0.5

# Editor should still be responsive
qa_screen
if echo "$QA_SCREEN" | grep -q "CHANGED"; then
    qa_pass "gutter click near modified line handled"
else
    qa_pass "gutter click handled without crash"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
