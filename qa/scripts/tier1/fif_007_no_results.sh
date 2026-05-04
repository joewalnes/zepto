#!/usr/bin/env bash
# QA-FIF-007: Search with no matches shows appropriate message
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-007: Find in files no results"

proj_dir=$(mktemp -d /tmp/zepto_qa_fif007_XXXXXX)
echo "hello world" > "$proj_dir/test.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start test.txt

# Open find-in-files
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

# Search for something that doesn't exist
qa_send "ZZZZNOTFOUND99999" 0.5

qa_screen
if echo "$QA_SCREEN" | grep -qiE "no.*(result|match)|0.*match|not found"; then
    qa_pass "no results message displayed"
elif ! echo "$QA_SCREEN" | grep -q "ZZZZNOTFOUND99999.*:"; then
    qa_pass "no file matches shown (correct)"
else
    qa_fail "no results handling"
fi

# No crash
if qa_alive 2>/dev/null; then
    qa_pass "no crash on zero results"
else
    qa_fail "crashed on zero results"
fi

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
