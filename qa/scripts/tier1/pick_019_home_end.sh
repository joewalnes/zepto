#!/usr/bin/env bash
# QA-PICK-019: Home/End in file picker
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PICK-019: Picker Home/End"

proj_dir=$(mktemp -d /tmp/zepto_qa_pick019_XXXXXX)
for i in $(seq -w 1 20); do echo "c$i" > "$proj_dir/file_${i}.txt"; done

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start file_01.txt

qa_keys "ctrl-p" 0.5

# End should jump to last item
qa_keys "end" 0.3

# Home should jump to first
qa_keys "home" 0.3

# Still in picker, files visible
qa_screen
if echo "$QA_SCREEN" | grep -qE "file_"; then
    qa_pass "home/end navigation in picker works"
else
    qa_fail "home/end in picker"
fi

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
