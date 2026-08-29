#!/usr/bin/env bash
# QA-PICK-004: Page Down in file picker
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-004: File picker Page Down"

proj_dir=$(mktemp -d /tmp/zepto_qa_pick004_XXXXXX)
for i in $(seq -w 1 30); do
    echo "content_$i" > "$proj_dir/file_${i}.txt"
done

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start file_01.txt

qa_keys "ctrl-p" 0.3

# Page Down
qa_keys "pagedown" 0.3

# Should still be in picker with files visible
qa_assert_expect "file_" "page down in picker shows files"

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
