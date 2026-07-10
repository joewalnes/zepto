#!/usr/bin/env bash
# QA-MS-023: Mouse press/drag dismisses active ghost completion
#
# bugs.md P2 "Mouse events never dismiss active ghost completion; stale
# suggestion re-renders at new cursor position": handle_mouse_event() never
# cancelled AI/word ghosts the way key handling did. Because
# Completion::Controller::state_for_render() always renders the ghost
# suffix at whatever the CURRENT cursor position is (it never checks that
# the cursor is still where the ghost was triggered), a still-active ghost
# reappears glued onto unrelated text after the cursor is moved elsewhere
# with the mouse — this is what this test actually reproduces and checks
# for, rather than just checking whether text moved. Fixed in Phase 2 via
# Editor::_dismiss_ghosts_for_mouse, called from both the mouse press and
# mouse drag text-area code paths.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-023: Mouse dismisses ghost completion"

# Screen layout: row 1 = tab bar, row 2 = ruler, row (2+N) = doc line N.
# Gutter is 7 cols wide for small files (get_gutter_width floors at 4
# digits + 3), so doc column C (0-indexed) is screen column 8+C.
#
# Line 1 seeds "myFunctionCall" as a known word. Line 2 is where we type a
# partial prefix to trigger cross-buffer word ghost completion (screen row
# 4). Line 3 (screen row 5, 19 chars) is a click target away from the
# completion point — we click at its end-of-line column (8+19=27) because
# the ghost renderer only draws ghost text when the cursor sits at EOL, so
# this is the position where a stale, un-dismissed ghost would visibly
# reappear glued onto line 3's text.
file=$(qa_tmpfile_nl "ms023.js" "myFunctionCall = 1

third line of text")
qa_start "$file"
qa_expect_screen "myFunctionCall" 5 -F || true

# Move to line 2 (empty) and type a partial prefix that word-completes
# against "myFunctionCall" from line 1.
qa_keys "down"
qa_send "myF"
sleep 0.8

qa_screen
line2_before=$(printf '%s' "$QA_SCREEN" | sed -n '4p')
if [[ "$line2_before" == *"myFunctionCall"* ]]; then
    qa_pass "ghost completion suggests full word on line 2 (myF + ghost suffix)"
else
    qa_fail "ghost completion did not trigger" "$line2_before"
fi

# Click at the end of line 3's text with the mouse — must dismiss the ghost
# AND move the cursor normally (not get swallowed by completion routing).
hangon mouse-click "$QA_SESSION" --x 27 --y 5
sleep 0.3

qa_assert_screen "3:" "cursor moved to line 3 — click was handled normally"

qa_screen
line3_after=$(printf '%s' "$QA_SCREEN" | sed -n '5p')
if [[ "$line3_after" == *"unctionCall"* ]]; then
    qa_fail "stale ghost suggestion re-rendered glued onto line 3 after mouse click" \
        "$line3_after"
else
    qa_pass "ghost completion dismissed after mouse click — no stale suffix on line 3"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
