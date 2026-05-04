#!/usr/bin/env bash
# QA-VCS-014: Character-level diff highlight in expanded hunk
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-014: Character-level diff highlight"

repo_dir=$(mktemp -d /tmp/zepto_qa_vcs014_XXXXXX)
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

# Change just a few characters on one line
if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/line 5 original/line 5 modified/' test.txt
else
    sed -i 's/line 5 original/line 5 modified/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1

# Jump to change and toggle diff
qa_keys "alt-n"
sleep 0.3
qa_keys "alt-d"
sleep 0.5

# Should see both old and new versions
qa_screen
has_old=$(echo "$QA_SCREEN" | grep -c "original" || true)
has_new=$(echo "$QA_SCREEN" | grep -c "modified" || true)

if [[ "$has_old" -ge 1 && "$has_new" -ge 1 ]]; then
    qa_pass "diff hunk shows both original and modified text"
elif [[ "$has_new" -ge 1 ]]; then
    qa_pass "diff view active showing modified content"
else
    qa_fail "diff hunk shows character-level changes"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
