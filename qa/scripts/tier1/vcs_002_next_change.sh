#!/usr/bin/env bash
# QA-VCS-002: Alt+N jumps to next VCS change
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-002: Jump to next VCS change"

# Create a git repo with committed content
repo_dir=$(mktemp -d /tmp/zepto_qa_vcs_XXXXXX)
cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create and commit initial file
content=""
for i in $(seq 1 30); do content+="line $i original"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"

# Modify line 15 to create a VCS change
# sed -i behaves differently on macOS vs Linux
if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/line 15 original/line 15 MODIFIED/' test.txt
else
    sed -i 's/line 15 original/line 15 MODIFIED/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1  # wait for VCS diff computation

# Should start at line 1
qa_assert_cursor_at 1 "starts at line 1"

# Jump to next change — should land on or near line 15
qa_keys "alt-n"
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 14 && "$QA_CURSOR_LINE" -le 16 ]]; then
    qa_pass "alt-n jumped to modified line ($QA_CURSOR_LINE)"
else
    qa_fail "alt-n jumped to modified line (at line $QA_CURSOR_LINE, expected ~15)"
fi

qa_keys "ctrl-q"

rm -rf "$repo_dir"
qa_summary
