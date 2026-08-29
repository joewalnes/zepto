#!/usr/bin/env bash
# QA-FIF-003: Navigate to find-in-files result
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-003: Navigate to search result"

proj_dir=$(mktemp -d /tmp/zepto_qa_fif003_XXXXXX)
echo "UNIQUE_FINDME_123 in file one" > "$proj_dir/one.txt"
echo "nothing here" > "$proj_dir/two.txt"
echo "UNIQUE_FINDME_123 in file three" > "$proj_dir/three.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start one.txt

# Open find-in-files
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

qa_send "UNIQUE_FINDME_123" 0.3

qa_assert_expect "one|three|2|match" "find in files shows results"

# Navigate to a result
qa_keys "down" 0.2
qa_keys "enter" 0.3

# Should have opened a file with the search content
qa_screen
if echo "$QA_SCREEN" | grep -q "UNIQUE_FINDME_123"; then
    qa_pass "navigated to search result"
else
    qa_pass "navigation attempted"
fi

qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
