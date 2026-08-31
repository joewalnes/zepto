#!/usr/bin/env bash
# QA-REG-202: Kitty/fixterms CSI-u modified special keys are not dropped
#
# bugs.md P3 "Kitty/fixterms CSI-u modified special keys (Ctrl+Enter,
# etc.) are silently and permanently dropped" — InputParser.pm's CSI-u
# handler (ESC [ codepoint ; modifiers u) only mapped codepoints in the
# printable range 32-126 to events. Enter (13), Tab (9), Backspace
# (8/127), and Escape (27) sent via this Kitty-protocol path with a
# modifier fell through to "Unknown CSI sequence" -> EVT_NONE and were
# silently, permanently dropped — e.g. Ctrl+Enter did nothing at all on a
# Kitty-protocol terminal.
#
# This is a real interactive repro, not just a unit test: raw CSI-u bytes
# are injected directly into zepto's pty via `hangon send --stdin` (no
# real Kitty-protocol terminal is needed — InputParser parses whatever
# bytes arrive on stdin regardless of what the terminal advertises), and
# the resulting editor behavior is observed on the rendered screen. Each
# assertion below uses the status bar's "line:col" position indicator
# (robust and format-stable) rather than the gutter cursor glyph, which
# varies between a plain ">" and a nerd-font powerline glyph depending on
# terminal capability detection and is not a reliable test signal.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-202: CSI-u special keys (Enter/Tab/Backspace/Escape) not dropped"

file=$(qa_tmpfile_nl "reg202.txt" "")
qa_start "$file"
qa_assert_expect "reg202" "file opened"

# --- Ctrl+Backspace via CSI-u (ESC [ 8 ; 5 u) -----------------------------
# Type "abc" (cursor -> line 1, col 4), then send backspace through the
# CSI-u path. Before the fix this byte sequence produced EVT_NONE and
# "abc"/1:4 would remain untouched; after the fix it must delete the last
# character and move the cursor back, same as plain Backspace.
qa_send "abc"
qa_assert_screen "abc" "typed abc"
qa_assert_screen "1:4" "cursor at 1:4 after typing abc"
printf '\x1b[8;5u' | qa_raw_stdin
qa_assert_not_screen "abc" "Ctrl+Backspace via CSI-u deleted the last char (abc -> ab)"
qa_assert_screen "1:3" "cursor moved back to 1:3 after Ctrl+Backspace"

# --- Ctrl+Enter via CSI-u (ESC [ 13 ; 5 u) --------------------------------
# Before the fix this was silently dropped: no new line, cursor unmoved
# (stuck at 1:3). After the fix it splits the line, same as plain Enter.
printf '\x1b[13;5u' | qa_raw_stdin
qa_assert_screen "2:1" "Ctrl+Enter via CSI-u split the line (cursor now at 2:1)"

# --- Ctrl+Tab via CSI-u (ESC [ 9 ; 5 u) -----------------------------------
# Before the fix this was silently dropped: cursor would stay at 2:1.
# After the fix it inserts a tab, same as plain Tab, advancing the column
# (exact width is a preference, so just assert it moved past column 1).
printf '\x1b[9;5u' | qa_raw_stdin
qa_assert_screen "2:[2-9]" "Ctrl+Tab via CSI-u advanced the cursor column (tab inserted)"
qa_assert_not_screen "2:1 " "cursor no longer sitting at column 1"

# --- Ctrl+Escape via CSI-u (ESC [ 27 ; 5 u) -------------------------------
# Open the command palette, then close it with Escape sent via CSI-u.
# "Commands" alone isn't a safe marker — it also appears in the bottom
# hint pill even when the palette is closed. The box-drawing "╭" corner is
# unique to an open dialog. Before the fix the CSI-u escape byte sequence
# was dropped and the palette would have stayed open.
qa_keys "ctrl-space"
qa_assert_screen "╭" "command palette opened (dialog box visible)"
printf '\x1b[27;5u' | qa_raw_stdin
qa_assert_not_screen "╭" "Ctrl+Escape via CSI-u closed the command palette"

qa_keys "ctrl-q"
qa_summary
