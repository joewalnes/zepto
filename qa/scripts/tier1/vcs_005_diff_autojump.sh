#!/usr/bin/env bash
# QA-VCS-005: Alt+D on unchanged line auto-jumps to next change
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-005: Diff auto-jump on unchanged line"

repo_dir=$(mktemp -d /tmp/zepto_qa_vcs005_XXXXXX)
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

content=""
for i in $(seq 1 30); do content+="line $i original"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"

if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/line 20 original/line 20 CHANGED/' test.txt
else
    sed -i 's/line 20 original/line 20 CHANGED/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1

# Cursor at line 1 (unchanged)
qa_assert_cursor_at 1 "starts at line 1"

# Toggle diff — should auto-jump to the change
qa_keys "alt-d"
sleep 0.5

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 18 && "$QA_CURSOR_LINE" -le 22 ]]; then
    qa_pass "alt-d auto-jumped to change at line $QA_CURSOR_LINE"
else
    qa_fail "alt-d auto-jumped to change" "cursor at line $QA_CURSOR_LINE, expected ~20"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
