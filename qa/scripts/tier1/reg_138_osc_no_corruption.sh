#!/usr/bin/env bash
# QA-REG-138: A terminal OSC response (e.g. a background-color query reply
# used for Linux auto-theme detection) arriving on stdin must not corrupt
# the document or leak into it as garbage keystrokes.
#
# Root cause (found while building P3 "Automatic dark/light mode"):
# InputParser::_parse_escape() had no recognition for "ESC ]" (OSC), so it
# fell into the generic "Alt+key" branch: ']' became Alt+']', and every
# following raw byte of the OSC payload/terminator was then parsed as its
# own ordinary character event — i.e. typed straight into the document if
# focus was in the editor. Fixed in InputParser::_parse_osc(), which
# recognizes and cleanly consumes OSC sequences (BEL- or ST-terminated)
# without emitting spurious char events. See tests/input_parser.t for the
# unit-level coverage (BEL-terminated, ST-terminated, split-across-reads,
# runaway/unterminated body, and the Alt+']' flush case).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-138: OSC sequence does not corrupt document"

file=$(qa_tmpfile "reg138.txt" "")
qa_start "$file"

# Simulate an unsolicited terminal OSC 11 (background color) response —
# exactly the shape a real terminal reply to a color query takes.
# BEL-terminated:
qa_raw "$(printf '\x1b]11;rgb:1a1a/1a1a/2626\x07')"
qa_assert_not_screen 'rgb' "No literal OSC payload text leaked into the buffer (BEL-terminated)"
qa_assert_not_screen '1a1a' "No fragment of the BEL-terminated OSC payload leaked in"

# ST-terminated (ESC followed by a single '\' byte — printf '\x1b\\'
# emits exactly ESC + one backslash; do not add extra backslashes here):
qa_raw "$(printf '\x1b]11;rgb:ffff/ffff/ffff\x1b\\')"
qa_assert_not_screen 'rgb' "No literal OSC payload text leaked into the buffer (ST-terminated)"
qa_assert_not_screen 'ffff' "No fragment of the ST-terminated OSC payload leaked in"

# A real keystroke sent right after must still work normally, and nothing
# from either OSC sequence (nor its Alt+']' misparse) should have landed
# before it.
qa_send "OK" 0.3
qa_assert_screen 'OK' "Real keystrokes after the OSC sequences are typed normally"
qa_assert_not_screen '\]OK' "No stray Alt+']' character landed just before the real keystrokes"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n" 0.2   # Discard the typed "OK" if prompted for unsaved changes
qa_summary
