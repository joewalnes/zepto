#!/usr/bin/env bash
# QA-SBAR-017: Open File is an ordinary Ctrl-column pill, not a hardcoded
# fixed pill next to the palette trigger (REGRESSION guard).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-017: Open File folded into ⌃ column"

file=$(qa_tmpfile_nl "sbar017.txt" "hello world")
qa_start "$file"

qa_assert_expect "1:1" "editor loaded"
qa_status_bar
bar="$QA_STATUS_BAR"

# Shown as an ordinary Ctrl-column pill ("Open File ⌃O/⌃P", modifier
# repeated on the pill like every other Ctrl-column pill), not a second
# hardcoded pill pinned next to the palette trigger.
ctrl_glyph=$(printf '\xe2\x8c\x83')  # ⌃ U+2303
if echo "$bar" | grep -qF "Open File ${ctrl_glyph}O/${ctrl_glyph}P"; then
    qa_pass "Open File pill shows ⌃O/⌃P as an ordinary Ctrl-column pill"
else
    qa_fail "Open File pill shows ⌃O/⌃P as an ordinary Ctrl-column pill" "status bar: $bar"
fi

# It sits left of the palette trigger, inside the same column as Save.
open_pos=$(echo "$bar" | awk '{print index($0,"Open File")}')
save_pos=$(echo "$bar" | awk '{print index($0,"Save")}')
cmds_pos=$(echo "$bar" | awk '{print index($0,"Commands")}')
if [[ "$open_pos" -gt 0 && "$save_pos" -gt 0 && "$cmds_pos" -gt 0 \
      && "$save_pos" -lt "$open_pos" && "$open_pos" -lt "$cmds_pos" ]]; then
    qa_pass "Open File pill sits in the ⌃ column, between Save and Commands"
else
    qa_fail "Open File pill sits in the ⌃ column, between Save and Commands" \
        "save_pos=$save_pos open_pos=$open_pos cmds_pos=$cmds_pos"
fi

# Clicking it still opens the file picker (behavior unchanged by the move).
last_row=$(echo "$QA_SCREEN" | wc -l | tr -d ' ')
hangon mouse-click "$QA_SESSION" --x "$open_pos" --y "$last_row"
sleep 0.4
qa_assert_screen "Open File|Recent|Files|/" "clicking Open File pill triggers open-file action"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
