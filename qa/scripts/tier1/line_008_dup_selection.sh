#!/usr/bin/env bash
# QA-LINE-008: Duplicate selected lines via palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-008: Duplicate selection"

file=$(qa_tmpfile_nl "line008.txt" "alpha
beta
gamma")
qa_start "$file"

# Select line 1
qa_keys "home"
qa_keys "shift-down" 0.1

# Duplicate down via Ctrl+Shift+Down or palette
qa_keys "ctrl-space"
qa_send "duplicate" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -qiE "duplicate.*down|duplicate line"; then
    qa_keys "enter"
    sleep 0.3
else
    qa_keys "escape" 0.2
    qa_keys "escape" 0.2
    # Try Ctrl+D shortcut for duplicate down
    qa_keys "ctrl-u"
fi

qa_screen
count=$(echo "$QA_SCREEN" | grep -c "alpha" || true)
if [[ $count -ge 2 ]]; then
    qa_pass "line duplicated ($count copies visible)"
else
    qa_fail "line duplicated (only $count copy visible)"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
