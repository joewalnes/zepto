#!/usr/bin/env bash
# QA-CPLT-021: Ctrl+Space is context-sensitive — completion menu mid-word,
# command palette otherwise (behavioral discovery).
#
# Editor.pm (~1292-1312): pressing Ctrl+Space when the character
# immediately before the cursor is a word character (\w) triggers the
# completion menu instead of opening the command palette. Discovered while
# writing qa/scripts/tier1/reg_021_new_file_tree.sh: a "ctrl-space -> type
# 'save as' -> enter" flow right after typing text silently typed "save as"
# into the document instead of running the Save As command, because the
# cursor was sitting right after a word character. reg_021 now avoids the
# ambiguity entirely by using Ctrl+S instead; this script documents and
# regression-guards the underlying dual behavior directly.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-021: Ctrl+Space context sensitivity"

file=$(qa_tmpfile "cplt021.txt" "")
qa_start "$file"

# Cursor at col 0 (nothing typed yet) — Ctrl+Space must open the palette.
qa_keys "ctrl-space"
qa_assert_screen "Copy|Paste|Undo|Redo" "Ctrl+Space at start of empty line opens the command palette"
qa_keys "escape"
sleep 0.2

# Type a word so the cursor sits immediately after a word character, then
# Ctrl+Space must open the completion menu, NOT the palette (the palette's
# default command list, e.g. "Copy"/"Paste", must NOT appear).
qa_send "hello"
sleep 0.2
qa_keys "ctrl-space"
sleep 0.3
qa_assert_not_screen "Copy.*⌃C" "Ctrl+Space mid-word does not open the command palette"

# Whatever it did trigger, the editor must still be alive and responsive —
# dismiss with Escape and confirm normal typing still works afterward.
qa_keys "escape"
sleep 0.2
qa_send " world"
qa_assert_screen "hello world" "editor still responsive after Ctrl+Space mid-word"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
