#!/usr/bin/env bash
# QA-FIF-013: ReDoS protection in find-in-files
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-013: ReDoS protection in FIF"

dir=$(qa_git_repo)
echo "aaaaaaaaaa" > target.txt
git add . && git commit -q -m "init"

qa_start target.txt

# Open find-in-files with regex
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

# Enable regex mode
qa_keys "ctrl-r" 0.2

# Try a very long pattern (>1000 chars)
long_pattern=$(python3 -c "print('a' * 1100)")
qa_send "$long_pattern" 0.5

# Editor should still be alive (pattern rejected or handled safely)
if qa_alive 2>/dev/null; then
    qa_pass "editor survives long regex pattern (>1000 chars)"
else
    qa_fail "editor crashed on long regex pattern"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
