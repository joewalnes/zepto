#!/usr/bin/env bash
# QA-REG-173: A compact status-bar pill (icon + key, label dropped) always
# shows its icon — never degrades to a bare, unlabeled key letter.
# Investigated (bugs.md "Discoverability sweep run 2"): an LLM-vision
# sweep flagged the compact Word Wrap pill as reading like a bare,
# context-free "Z". Root-caused against the live byte stream and the
# rendered PNG: Zepto::Chars.pm's ASCII fallback for every priority > 0
# command's icon (including 'wrap' -> 'W') IS present and non-empty in
# both nerd-font and ASCII modes — confirmed via
# `Zepto::Chars->get('wrap')` returning 'W' in ASCII mode, and via this
# exact live screen capture. The apparent "bare Z" was the LLM-vision
# sweep's screenshot renderer not having a patched Nerd Font for one
# specific PUA glyph (\x{f036}) while rendering others fine — a
# screenshot-tool font-completeness artifact, not a Zepto bug (compare:
# --no-nerd-font mode is plain ASCII 'W', immune to any font-completeness
# question, and still shows correctly below).
# See tests/renderer.t "No priority > 0 command ever compacts to a bare
# key with no icon" for the general, whole-registry regression guard.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-173: Compact status-bar pill shows icon + key, not a bare key"

file=$(qa_tmpfile_nl "reg173.txt" "hello world")
qa_start --no-nerd-font "$file"
qa_assert_expect "reg173" "file is open"

# Removing the standalone ⌃/⌥ column-header glyph (see QA-SBAR-016) freed
# up 6 columns, so the default 80-column session now fits "Word Wrap ⌥Z"
# in full form — narrow the terminal to force the compact path this test
# is actually about.
qa_resize_window 74 24

# At this width, the ⌥ column's Word Wrap pill renders in compact form
# ("W ⌥Z" = icon 'W' + modifier+key '⌥Z'), not full form — this is the
# exact pill the LLM-vision sweep flagged. Assert the icon character is
# actually there, immediately before the key.
alt_glyph=$(printf '\xe2\x8c\xa5')  # ⌥ U+2325
qa_assert_screen "W[[:space:]]+${alt_glyph}Z" "Word Wrap compact pill shows icon 'W' before key '⌥Z' (not bare)"

qa_keys "ctrl-q"
qa_summary
