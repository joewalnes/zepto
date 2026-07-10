#!/usr/bin/env bash
# QA-MS-021: Mouse drag creates a multi-line selection
#
# Uses qa_mouse_drag_gesture (raw SGR injection) rather than hangon's
# built-in `mouse-drag` — see the comment above qa_mouse_press in
# qa-helpers.sh for why: hangon's mouse-drag encodes the SGR press/release
# final byte backwards relative to Zepto's (standards-compliant) parser, so
# a drag driven through it never actually lands as a drag. Discovered while
# fixing QA-MS-012 (drag tree border).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-021: Drag selects text across lines"

file=$(qa_tmpfile_nl "ms021.txt" "line one
line two
line three
line four
line five")
qa_start "$file"
qa_expect_screen "line one" 5 -F || true  # guarded: set -e would kill the script on timeout

# Screen layout: row 1 = tab bar, row 2 = ruler, row 3 = doc line 1, ...
# row (2 + N) = doc line N. Gutter + " " is 7 cols wide here (5-digit-wide
# line number field), so doc column C on a given row is screen column 7+C.
# Drag from line 4, col 3 up to line 2, col 5 (deliberately reversed/upward,
# per the QA-MS-022 known-bug scenario this pairs with).
qa_mouse_drag_gesture 10 6 12 4 5
sleep 0.3

# Cut the selection and verify what's left — a real assertion that can only
# pass if the drag actually selected the expected range. Dragging from
# (line4,col3) to (line2,col5) selects " two\nline three\nli" (the region
# between line2 col5 and line4 col3), so cutting it merges what remains of
# line 2 ("line") with what remains of line 4 ("ne four") into one line.
qa_keys "ctrl-x"
qa_expect_screen "linene four" 3 -F || true  # fall through to the real assertion below either way

qa_assert_screen "linene four" "drag selection spanned line 2 to line 4 as expected"
qa_assert_not_screen "line two" "line 2's cut portion is gone"
qa_assert_not_screen "line three" "line 3 (fully inside the selection) is gone"
qa_assert_screen "line one" "line 1 (outside selection) is untouched"
qa_assert_screen "line five" "line 5 (outside selection) is untouched"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
