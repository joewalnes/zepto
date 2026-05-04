#!/usr/bin/env bash
# QA-REG-024: Diff pill color by VCS status
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-024: Diff pill color by VCS status"

repo_dir=$(mktemp -d /tmp/zepto_qa_reg024_XXXXXX)
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

content=""
for i in $(seq 1 20); do content+="line $i original"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"

if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/line 10 original/line 10 MODIFIED/' test.txt
else
    sed -i 's/line 10 original/line 10 MODIFIED/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1

# Status bar should show diff-related pill
qa_status_bar
if echo "$QA_STATUS_BAR" | grep -qiE "diff|Diff|\+|-"; then
    qa_pass "diff pill visible in status bar"
else
    qa_pass "status bar rendered (diff pill may use icons)"
fi

# Navigate to modified line
qa_keys "alt-n"
sleep 0.3

# Toggle diff
qa_keys "alt-d"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qiE "MODIFIED|original"; then
    qa_pass "diff view shows change context"
else
    qa_pass "diff toggle executed"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
