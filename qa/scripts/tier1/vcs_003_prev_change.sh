#!/usr/bin/env bash
# QA-VCS-003: Alt+P jumps to previous VCS change
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-003: Jump to prev VCS change"

# Create a git repo with committed content
repo_dir=$(mktemp -d /tmp/zepto_qa_vcs_XXXXXX)
cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create and commit initial file with many lines
content=""
for i in $(seq 1 50); do content+="line $i original"$'\n'; done
printf '%s' "$content" > test.txt
git add test.txt
git commit -q -m "initial"

# Modify lines 10 and 40 to create two VCS changes
if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' 's/line 10 original/line 10 MODIFIED/' test.txt
    sed -i '' 's/line 40 original/line 40 MODIFIED/' test.txt
else
    sed -i 's/line 10 original/line 10 MODIFIED/' test.txt
    sed -i 's/line 40 original/line 40 MODIFIED/' test.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/test.txt"
sleep 1  # wait for VCS diff computation

# Jump to last line so we can go backwards
qa_keys "ctrl-g"
qa_send "50" 0.2
qa_keys "enter"

# Prev change — should land near line 40
qa_keys "alt-p"
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 38 && "$QA_CURSOR_LINE" -le 42 ]]; then
    qa_pass "alt-p jumped to modified line 40 ($QA_CURSOR_LINE)"
else
    qa_fail "alt-p jumped to modified line 40 (at line $QA_CURSOR_LINE)"
fi

# Prev change again — should land near line 10
qa_keys "alt-p"
sleep 0.3

qa_cursor_pos
if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge 8 && "$QA_CURSOR_LINE" -le 12 ]]; then
    qa_pass "second alt-p jumped to modified line 10 ($QA_CURSOR_LINE)"
else
    qa_fail "second alt-p jumped to modified line 10 (at line $QA_CURSOR_LINE)"
fi

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
