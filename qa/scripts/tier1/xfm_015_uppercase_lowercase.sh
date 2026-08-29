#!/usr/bin/env bash
# QA-XFM-015: Uppercase / Lowercase transform the selection, or the
# whole document if nothing is selected (same scoping as ⌥T).
#
# NOTE: ⌃Space is context-sensitive — if the cursor sits immediately
# after a word character, it triggers word completion instead of
# opening the palette (Editor.pm::handle_ctrl_char, char ' ' case;
# pre-existing, unrelated to this feature). Home is pressed before
# ⌃Space below specifically to land the cursor at column 0, sidestepping
# that ambiguity.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-015: Uppercase / Lowercase"

file=$(qa_tmpfile_nl "xfm015.txt" "one
two
three")
qa_start "$file"

# Select "one" (line 1) only.
qa_keys "home" 0.2
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
qa_keys "shift-right" 0.1
# Extend selection one more char (onto the newline) so the cursor is
# NOT immediately after a word character before opening the palette.
qa_keys "shift-right" 0.2

qa_keys "ctrl-space"
qa_assert_expect "Commands" "palette opened with selection active"
qa_send "Uppercase" 0.3
qa_keys "enter" 0.3

qa_assert_expect "ONE" "selected word uppercased"
qa_assert_not_screen "TWO" "unselected line 'two' was not uppercased"
qa_assert_not_screen "THREE" "unselected line 'three' was not uppercased"

qa_keys "ctrl-z" 0.3
qa_assert_expect "one" "undo restores lowercase 'one'"
qa_assert_not_screen "ONE" "no uppercase remnant after undo"

# Lowercase with NO selection — whole-document scope.
qa_keys "home" 0.2
qa_keys "end" 0.2
qa_keys "enter" 0.2
qa_send "HELLO" 0.2

qa_keys "home" 0.2
qa_keys "ctrl-space"
qa_assert_expect "Commands" "palette opened with no selection"
qa_send "Lowercase" 0.3
qa_keys "enter" 0.3

qa_assert_expect "hello" "whole document (including new HELLO line) lowercased"
qa_assert_not_screen "HELLO" "no uppercase remnant after whole-document Lowercase"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
