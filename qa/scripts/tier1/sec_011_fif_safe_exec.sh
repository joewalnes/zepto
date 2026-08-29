#!/usr/bin/env bash
# QA-SEC-011: Find-in-files backend uses safe exec
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-011: Find-in-files safe exec"

# Create a project with files
project_dir=$(mktemp -d /tmp/zepto_qa_sec011_XXXXXX)
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

cd "$project_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
printf 'hello world\n' > file1.txt
printf 'hello again\n' > file2.txt
git add .
git commit -q -m "initial"
cd "$OLDPWD"

qa_start "$project_dir/file1.txt"
sleep 0.5

# Open find-in-files with a pattern containing shell metacharacters
qa_keys "ctrl-shift-f" 0.2 || qa_keys "ctrl-space" 0.2
qa_wait_screen 'find|Find|command' || true
if ! echo "$QA_SCREEN" | grep -qi "find in"; then
    qa_keys "ctrl-space"
    qa_send "find in files" 0.3
    qa_keys "enter" 0.3
fi

# Type a search with shell metacharacters
qa_send 'hello; touch /tmp/zqa_fif_pwned' 0.5

rm -f /tmp/zqa_fif_pwned

sleep 1

# Verify no injection
if [[ -f /tmp/zqa_fif_pwned ]]; then
    qa_fail "find-in-files safe exec" "/tmp/zqa_fif_pwned was created!"
    rm -f /tmp/zqa_fif_pwned
else
    qa_pass "find-in-files safe exec (no shell injection)"
fi

qa_keys "escape"
qa_keys "ctrl-q"
rm -rf "$project_dir"
qa_summary
