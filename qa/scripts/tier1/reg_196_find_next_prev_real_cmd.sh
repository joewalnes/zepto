#!/usr/bin/env bash
# QA-REG-196: cmd_find_next/cmd_find_prev (Ctrl+J / Ctrl+K) actually
# navigate between matches once a search term is set.
#
# Regression context: bugs.md "do_find_next/do_find_prev are 77 lines of
# dead production code" — a dead, unit-test-only implementation
# (Editor::do_find_next/do_find_prev) shadowed the real, palette- and
# key-bound commands (cmd_find_next/cmd_find_prev, Ctrl+J/Ctrl+K) with
# similar names. Deleting the dead code left the real commands with zero
# interactive coverage (find.t/editor.t only exercise the lower-level
# _find_navigate() directly, never the Ctrl+J/Ctrl+K entry points). This
# script closes that gap end-to-end through the real UI.
#
# Each check below resets the cursor to a known position with Ctrl+G
# immediately before pressing Ctrl+J/Ctrl+K, rather than chaining off the
# previous find action's landing spot. cmd_find_next/cmd_find_prev each
# re-anchor to the match nearest the CURRENT cursor (via enter_find_mode)
# before stepping — so chaining calls can (correctly, if confusingly)
# land back where you started when the cursor is sitting exactly on a
# match boundary. That's a real, separately-notable quirk (see bugs.md),
# not a reason to write a flaky test — resetting position keeps this
# script deterministic.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-196: Find Next/Prev (Ctrl+J/Ctrl+K) real command navigation"

file=$(qa_tmpfile_nl "reg196.txt" "MARKER one
line two
MARKER three
line four
MARKER five")
qa_start "$file"

# Set a search term via the normal find bar, then dismiss it — the real
# user flow that populates search_term for later Ctrl+J/Ctrl+K use.
qa_keys "ctrl-f"
qa_send "MARKER" 0.3
qa_keys "escape"
qa_wait_screen '[0-9]+:[0-9]+ .*⌃G' 5 || true

goto() {
    # goto LINE:COL — deterministic cursor reset via the Goto Line dialog
    qa_keys "ctrl-g"
    qa_keys "ctrl-a" 0.1
    qa_send "$1" 0.2
    qa_keys "enter"
    qa_wait_screen '[0-9]+:[0-9]+ .*⌃G' 5 || true
}

# --- Find Next (Ctrl+J) from a known baseline (start of doc) ---
goto "1:1"
qa_keys "ctrl-j"
qa_assert_expect '2 of 3' "Ctrl+J (Find Next) from the top lands on the 2nd of 3 matches"
qa_keys "escape"
# Cursor-position pill format is "<icon> L:C ⌃G ..." — match the "3:N"
# substring rather than anchoring to line start (the pill is prefixed by
# a Nerd Font icon glyph, not just spaces).
qa_assert_expect '3:[0-9]+ .*⌃G' "Ctrl+J moved the cursor onto line 3 (the 2nd match)"

# --- Find Prev (Ctrl+K) from a known baseline (end of doc) ---
goto "5:1"
qa_keys "ctrl-k"
qa_assert_expect '2 of 3' "Ctrl+K (Find Prev) from the bottom lands on the 2nd of 3 matches"
qa_keys "escape"
qa_assert_expect '3:[0-9]+ .*⌃G' "Ctrl+K moved the cursor onto line 3 (the 2nd match)"

# --- Discoverability: both commands are reachable from the palette ---
qa_keys "ctrl-space"
qa_send "Find Next" 0.3
qa_assert_expect 'Find Next' "Find Next is in the command palette"
qa_keys "escape"

qa_keys "ctrl-space"
qa_send "Find Prev" 0.3
qa_assert_expect 'Find Prev' "Find Prev is in the command palette"
qa_keys "escape"

qa_keys "ctrl-q"
qa_summary
