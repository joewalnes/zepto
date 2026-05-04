#!/usr/bin/env bash
# QA-PICK-002: File picker navigation and selection
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-002: File picker navigation"

proj_dir=$(mktemp -d /tmp/zepto_qa_pick002_XXXXXX)
echo "content_aaa" > "$proj_dir/aaa.txt"
echo "content_bbb" > "$proj_dir/bbb.txt"
echo "content_ccc" > "$proj_dir/ccc.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start aaa.txt

# Open file picker
qa_keys "ctrl-p" 0.3

# Should show file list
qa_assert_screen "bbb|ccc" "picker shows other files"

# Navigate down and select
qa_keys "down" 0.2
qa_keys "enter" 0.3

# Should have opened a different file
qa_screen
if echo "$QA_SCREEN" | grep -qE "content_bbb|content_ccc"; then
    qa_pass "picker opened selected file"
else
    qa_fail "picker opened selected file"
fi

qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
