#!/usr/bin/env bash
# QA-PAL-022: Page Down/Up in command palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-022: Palette page nav"

file=$(qa_tmpfile_nl "pal022.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
sleep 0.3

# Page Down
qa_keys "pagedown" 0.3

# Should still be in palette
qa_screen
if echo "$QA_SCREEN" | grep -qiE "Commands|FILE|EDIT|Save|Open|Theme"; then
    qa_pass "page down in palette works"
else
    qa_fail "page down in palette"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
