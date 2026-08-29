#!/usr/bin/env bash
# QA-SBAR-016: Ctrl pills grouped left, Alt pills grouped right, modifier shown once
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-016: Ctrl/Alt modifier-grouped columns"

file=$(qa_tmpfile_nl "sbar016.txt" "hello world")
qa_start "$file"

qa_assert_expect "1:1" "editor loaded"
qa_status_bar
bar="$QA_STATUS_BAR"

# Ctrl group: Save pill present with a bare key badge, not a repeated ⌃.
if echo "$bar" | grep -qE "Save[[:space:]]+S([[:space:]]|$)"; then
    qa_pass "Ctrl group shows Save pill with bare key (no repeated ⌃)"
else
    qa_fail "Ctrl group shows Save pill with bare key" "status bar: $bar"
fi
ctrl_glyph=$(printf '\xe2\x8c\x83')  # ⌃ U+2303
if echo "$bar" | grep -qF "Save ${ctrl_glyph}S"; then
    qa_fail "Save pill does not repeat the ⌃ glyph" "status bar: $bar"
else
    qa_pass "Save pill does not repeat the ⌃ glyph before its key"
fi

# Alt group: the ⌥ label glyph is present.
if echo "$bar" | grep -qF "$(printf '\xe2\x8c\xa5')"; then
    qa_pass "Alt (⌥) group label visible"
else
    qa_fail "Alt (⌥) group label visible" "status bar: $bar"
fi

# Ordering: Ctrl column (Save) renders left of the Alt column, which
# renders left of the always-rightmost Commands/palette pill.
save_pos=$(echo "$bar" | awk '{print index($0,"Save")}')
alt_pos=$(echo "$bar" | awk -v c="$(printf '\xe2\x8c\xa5')" '{print index($0,c)}')
cmds_pos=$(echo "$bar" | awk '{print index($0,"Commands")}')

if [[ "$save_pos" -gt 0 && "$alt_pos" -gt 0 && "$cmds_pos" -gt 0 \
      && "$save_pos" -lt "$alt_pos" && "$alt_pos" -lt "$cmds_pos" ]]; then
    qa_pass "Layout order: Ctrl group < Alt group < Commands pill"
else
    qa_fail "Layout order: Ctrl group < Alt group < Commands pill" \
        "save_pos=$save_pos alt_pos=$alt_pos cmds_pos=$cmds_pos"
fi

qa_keys "ctrl-q"
qa_summary
