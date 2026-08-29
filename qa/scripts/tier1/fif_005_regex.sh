#!/usr/bin/env bash
# QA-FIF-005: Find in files with regex pattern
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-005: Find in files regex"

proj_dir=$(mktemp -d /tmp/zepto_qa_fif005_XXXXXX)
echo "foo123bar" > "$proj_dir/match.txt"
echo "no match here" > "$proj_dir/nomatch.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start match.txt

# Open find-in-files
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

# Search with a pattern
qa_send "foo123" 0.3

qa_assert_expect "match|1|foo123" "find in files regex search works"

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
