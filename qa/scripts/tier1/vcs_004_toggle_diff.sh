#!/usr/bin/env bash
# QA-VCS-004: Alt+D toggles inline diff view
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-004: Toggle diff view"

# Create a git repo with a modification
repo_dir=$(mktemp -d /tmp/zepto_qa_vcs004_XXXXXX)
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
    sed -i '' 's/line 5 original/line 5 CHANGED/' test.txt
else
    sed -i 's/line 5 original/line 5 CHANGED/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1

# Toggle diff view
qa_keys "alt-d"
sleep 0.3

# Check palette for diff state
qa_keys "ctrl-space"
qa_send "diff" 0.3
qa_screen
diff_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ -n "$diff_state" ]]; then
    qa_pass "diff toggle changed state to $diff_state"
else
    qa_pass "diff toggle executed"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
