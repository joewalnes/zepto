#!/usr/bin/env bash
# QA-NAV-008+009: Page Down/Up scrolls by viewport
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-008: Page Down/Up"

content=""
for i in $(seq 1 200); do
    content+="line $i of the test file"$'\n'
done
file=$(qa_tmpfile_nl "nav008.txt" "$content")
qa_start "$file"

qa_assert_screen "1:1" "starts at top"

# Page down
qa_keys "pagedown"
qa_screen
# Should have advanced significantly (not still at line 1)
if echo "$QA_SCREEN" | grep -qE "line (2[0-9]|3[0-9]|4[0-9])"; then
    qa_pass "page down scrolled viewport"
else
    qa_fail "page down scrolled viewport"
fi

# Page up should go back
qa_keys "pageup"
qa_assert_screen "line 1 " "page up returned to top area"

qa_keys "ctrl-q"
qa_summary
