#!/usr/bin/env bash
# QA-FIF-004: Find in files with case toggle
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-004: Find in files case sensitivity"

proj_dir=$(mktemp -d /tmp/zepto_qa_fif004_XXXXXX)
echo "Hello World" > "$proj_dir/upper.txt"
echo "hello world" > "$proj_dir/lower.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start upper.txt

# Open find-in-files via palette
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

# Search for uppercase "Hello"
qa_send "Hello" 0.3

qa_assert_expect "upper|1|match" "case-sensitive search found match"

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
