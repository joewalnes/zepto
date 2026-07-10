#!/usr/bin/env bash
# QA-MS-012: Drag tree border resizes tree panel
#
# NOTE: uses qa_mouse_drag_gesture (raw SGR injection) instead of hangon's
# built-in `mouse-drag` — see qa-helpers.sh comment above qa_mouse_press for
# why: hangon's mouse-drag encodes the SGR press/release final byte backwards
# relative to Zepto's (standards-compliant) parser, so the drag never landed.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-012: Drag tree border resize"

file=$(qa_tmpfile_nl "ms012.txt" "hello world test content here that is long enough to see")
qa_start "$file"
qa_expect_screen "hello world" 5 -F || true

# Open tree, then WAIT for the tree panel to actually render (separator │
# visible) rather than a fixed sleep — under `make qa`'s parallel load a
# 0.5s sleep is not always enough, and measuring the separator column
# before the tree has painted made this test flaky in full runs.
qa_keys "ctrl-b"
qa_expect_screen $'│' 5 -F || true

# Default tree panel width is 23 cols, so the draggable border sits at
# column 24 (panel_width + 1). Measure the separator column before drag,
# using a character-index (not byte-offset) count since tree rows contain
# multi-byte nerd-font/PUA icons ahead of the separator.
qa_screen
sep_col_before=$(echo "$QA_SCREEN" | perl -CS -ne 'if ($. == 3) { print index($_, "\x{2502}") + 1; exit }')

# Drag the border from column 24 to column 40 (widen the tree)
qa_mouse_drag_gesture 24 3 40 3 5

# Poll until the separator has actually moved (render under load can lag
# past any single fixed sleep), up to a 5s ceiling.
sep_col_after=""
_deadline=$(( $(date +%s) + 5 ))
while true; do
    qa_screen
    sep_col_after=$(echo "$QA_SCREEN" | perl -CS -ne 'if ($. == 3) { print index($_, "\x{2502}") + 1; exit }')
    [[ -n "$sep_col_after" && -n "$sep_col_before" && "$sep_col_after" -gt "$sep_col_before" ]] && break
    [[ $(date +%s) -ge $_deadline ]] && break
    sleep 0.2
done

if [[ -n "$sep_col_before" && "$sep_col_before" -gt 0 && -n "$sep_col_after" && "$sep_col_after" -gt "$sep_col_before" ]]; then
    qa_pass "tree border drag widened the panel (separator moved from col $sep_col_before to $sep_col_after)"
else
    qa_fail "tree border drag widened the panel" "separator before=$sep_col_before after=$sep_col_after"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
