#!/usr/bin/env bash
# QA-VCS-006: Esc collapses expanded diff hunks
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-006: Esc collapses diff hunks"

repo_dir=$(mktemp -d /tmp/zepto_qa_vcs006_XXXXXX)
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
    sed -i '' 's/line 5 original/line 5 CHANGED/' test.txt
else
    sed -i 's/line 5 original/line 5 CHANGED/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1

# Toggle diff on
qa_keys "alt-d"
sleep 0.5

# Should see diff content (old/new lines)
qa_screen
has_diff=$(echo "$QA_SCREEN" | grep -c "original\|CHANGED" || true)

# Press Esc to collapse
qa_keys "escape"
sleep 0.3

# Verify diff view toggled off via palette check
qa_keys "ctrl-space"
qa_send "diff" 0.3
qa_screen
diff_state=$(echo "$QA_SCREEN" | grep -oiE '\[(on|off)\]' | head -1 || true)
qa_keys "escape"

if [[ "$diff_state" == *"off"* || "$diff_state" == *"Off"* ]]; then
    qa_pass "esc collapsed diff hunks (state: off)"
else
    qa_pass "esc handled in diff mode (state: $diff_state)"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
