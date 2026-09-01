#!/usr/bin/env bash
# QA-REG-215: Ghost-text completion (word-completion suggestion preview)
# renders at the cursor's actual screen column, not at the visual end of
# the line's real content.
#
# Bug: bugs.md P1 "Ghost-text completion renders at the end of the line's
# real content, not at the cursor -- garbles arbitrary lines when cursor
# isn't at line-end". Renderer.pm's ghost-text block always painted the
# suggestion suffix starting at $content_display_width (the end of the
# line's REAL content) instead of the cursor's screen column. Invisible
# when the cursor sits at true end-of-line (the common typing case), but
# garbled the display whenever the cursor was genuinely mid-line with real
# content still after it (e.g. after navigating back into a word, or the
# undo/redo-leaves-stale-cursor and multi-byte-navigation repros in
# bugs.md).
#
# Fix: Renderer.pm now computes the ghost text's screen column from the
# cursor's actual visual position (reusing the same tab/wide-char-aware
# _char_to_visual_col computation used elsewhere for the real block
# cursor). When the cursor is genuinely mid-line, the suggestion is
# painted as a same-row terminal overlay positioned exactly at the
# cursor -- the real content already rendered is never spliced, shifted,
# or duplicated (verified by save-to-disk staying byte-identical to what
# was on disk before the ghost text ever appeared).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-215: ghost-text completion renders at the cursor, not line-content end"

# Line 1 supplies two completion candidates for prefix "ban": "banana"
# (suffix "ana") and "bandana" (suffix "dana"). Line 2 starts as "ban XYZ"
# -- "ban" is the prefix being completed, " XYZ" is unrelated real content
# that sits AFTER the cursor once positioned mid-line. Uses a .dat
# extension so word wrap defaults off (Preferences::WRAP_DEFAULT_EXTENSIONS
# turns wrap on for .txt/.md, which is irrelevant noise for this test).
file=$(qa_tmpfile_nl "reg215.dat" "$(printf 'banana bandana\nban XYZ')")
qa_start "$file"

# Move to line 2, column 4 (0-indexed char col 3) -- immediately after
# "ban", immediately before " XYZ". Line 2 already starts at column 1, so
# three Right presses land exactly after "ban".
qa_keys "down" 0.2
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.2
qa_assert_cursor_at "2:4" "cursor positioned immediately after \"ban\", before \" XYZ\""

# Re-trigger word-completion at this exact mid-line position: delete the
# "n" and retype it (a plain insert, exactly the event Completion::Controller
# listens for) so the ghost text is (re)computed against the CURRENT,
# mid-line cursor -- not a stale one.
qa_keys "backspace" 0.2
qa_send "n" 0.5

# Isolate doc line 2's own screen row by its FIXED row position (tab bar =
# row 1, ruler = row 2, first text row = row 3 -> doc line 1, second text
# row = row 4 -> doc line 2; this 2-line fixture never scrolls or wraps).
# Deliberately NOT anchored on the gutter's line-number digit: the cursor
# line's gutter renders a badge (round-bracket + arrow glyphs) instead of
# plain leading spaces, which made a "digit at start of line" regex
# false-negative during development of this script. Isolating by row also
# avoids a tautology that a whole-screen match would have: line 1's own
# fixed content ("banana bandana") already contains the literal substring
# "bandana", so a plain whole-screen search for "ban(ana|dana)" would pass
# even if line 2 were never touched at all.
qa_screen
line2_row=$(echo "$QA_SCREEN" | sed -n '4p')

# The bug's signature: the ghost suffix glued onto the end of the REAL
# content, i.e. right after "XYZ" (reading "...XYZana" or "...XYZdana").
# That must not appear on line 2's row.
if echo "$line2_row" | grep -qE 'XYZ(ana|dana)'; then
    qa_fail "ghost text does not render after real trailing content (pre-fix bug shape)" "row: $line2_row"
else
    qa_pass "ghost text does not render after real trailing content (pre-fix bug shape)"
fi

# The fix's signature: the ghost suffix appears immediately after "ban",
# extending the visible word to "banana" or "bandana" (a real prefix match
# for both candidates) right at the cursor, with the " XYZ" tail (or
# whatever of it the equal-length overlay doesn't cover) still on the same
# row -- never on a different line, never duplicated elsewhere on screen.
if echo "$line2_row" | grep -qE 'ban(ana|dana)'; then
    qa_pass "ghost text renders immediately at the cursor, right after \"ban\""
else
    qa_fail "ghost text renders immediately at the cursor, right after \"ban\"" "row: $line2_row"
fi

# Cursor itself must not have moved just from the completion recomputing.
qa_assert_cursor_at "2:4" "cursor stays at the mid-line position while ghost text is showing"

# The OTHER line (unrelated real content) must render completely
# untouched -- confirms the ghost overlay never bled onto a different row
# (the "row1textw989text" shape from the original bugs.md repro).
qa_assert_screen 'banana bandana' "line 1 (source of the candidates) renders untouched"

# Accept the suggestion (Tab inserts the full ghost text at the cursor,
# independent of rendering -- this exercises that acceptance still lands
# in the right place now that the PREVIEW position is also correct).
qa_keys "tab" 0.3
qa_assert_screen 'ban(ana|dana) XYZ' "accepting inserts the suffix at the cursor, correctly pushing \" XYZ\" to the right"

# Save and confirm the file on disk matches exactly what is now on
# screen -- no corruption, no duplication, no stray characters snuck in
# via the overlay technique.
qa_keys "ctrl-s" 0.3
if grep -qE '^ban(ana|dana) XYZ$' "$file"; then
    qa_pass "saved file content matches the accepted completion exactly (no corruption)"
else
    qa_fail "saved file content matches the accepted completion exactly" "$(cat "$file")"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
