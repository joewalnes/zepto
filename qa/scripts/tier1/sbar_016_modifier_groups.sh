#!/usr/bin/env bash
# QA-SBAR-016: Ctrl pills grouped left, Alt pills grouped right, each pill
# shows its own modifier glyph
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-016: Ctrl/Alt modifier-grouped columns"

file=$(qa_tmpfile_nl "sbar016.txt" "hello world")
qa_start "$file"
qa_resize_window 145 40  # wide enough for both groups' full-text pills

qa_assert_expect "1:1" "editor loaded"
qa_status_bar
bar="$QA_STATUS_BAR"

# Ctrl group: Save pill repeats the ⌃ glyph on the pill itself. An earlier
# design showed the modifier once per column as a shared header, but
# direct user feedback found that made individual pills hard to read in
# isolation ("I just saw 'T' but not '^T'") -- see docs/UI_GUIDELINES.md.
ctrl_glyph=$(printf '\xe2\x8c\x83')  # ⌃ U+2303
if echo "$bar" | grep -qF "Save ${ctrl_glyph}S"; then
    qa_pass "Ctrl group: Save pill repeats the ⌃ glyph"
else
    qa_fail "Ctrl group: Save pill repeats the ⌃ glyph" "status bar: $bar"
fi

# Alt group: Word Wrap pill repeats the ⌥ glyph on the pill itself.
alt_glyph=$(printf '\xe2\x8c\xa5')  # ⌥ U+2325
if echo "$bar" | grep -qF "Word Wrap ${alt_glyph}Z"; then
    qa_pass "Alt group: Word Wrap pill repeats the ⌥ glyph"
else
    qa_fail "Alt group: Word Wrap pill repeats the ⌥ glyph" "status bar: $bar"
fi

# There is no standalone column-header glyph anymore -- the modifier is
# only ever attached to a pill, never rendered on its own between spaces.
if echo "$bar" | grep -qE "[[:space:]]${ctrl_glyph}[[:space:]]"; then
    qa_fail "No standalone ⌃ header separate from a pill" "status bar: $bar"
else
    qa_pass "No standalone ⌃ header separate from a pill"
fi
if echo "$bar" | grep -qE "[[:space:]]${alt_glyph}[[:space:]]"; then
    qa_fail "No standalone ⌥ header separate from a pill" "status bar: $bar"
else
    qa_pass "No standalone ⌥ header separate from a pill"
fi

# Ordering: Ctrl column (Save) renders left of the Alt column (Word Wrap),
# which renders left of the always-rightmost Commands/palette pill.
save_pos=$(echo "$bar" | awk '{print index($0,"Save")}')
wrap_pos=$(echo "$bar" | awk '{print index($0,"Word Wrap")}')
cmds_pos=$(echo "$bar" | awk '{print index($0,"Commands")}')

if [[ "$save_pos" -gt 0 && "$wrap_pos" -gt 0 && "$cmds_pos" -gt 0 \
      && "$save_pos" -lt "$wrap_pos" && "$wrap_pos" -lt "$cmds_pos" ]]; then
    qa_pass "Layout order: Ctrl group < Alt group < Commands pill"
else
    qa_fail "Layout order: Ctrl group < Alt group < Commands pill" \
        "save_pos=$save_pos wrap_pos=$wrap_pos cmds_pos=$cmds_pos"
fi

qa_keys "ctrl-q"
qa_summary
