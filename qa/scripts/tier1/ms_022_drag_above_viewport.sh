#!/usr/bin/env bash
# QA-MS-022: Drag above the text viewport in word-wrap mode should clamp to
# document start, not jump to the end.
#
# bugs.md: "P1: Mouse drag above first visual row in word-wrap mode jumps
# selection/view to end of document" — WrapMap::visual_to_doc
# (WrapMap.pm:386-393) returned the LAST document line whenever
# segment_at_visual_row($vrow) failed to find a segment, which happened both
# when $vrow was beyond the last row (correct clamp) and when $vrow was
# negative, i.e. above the first row (incorrect — should clamp to line 0,
# col 0 instead).
#
# Fixed in Phase 2: negative/underflow $vrow now clamps to (0, 0) in
# WrapMap::visual_to_doc. This is now a hard regression assertion.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-022: Drag above viewport in wrap mode (KNOWN-BUG repro)"

# Long lines so word wrap actually wraps them.
file=$(qa_tmpfile_nl "ms022.txt" "line one of the document with some extra padding text to make it longer for wrap testing purposes maybe
line two of the document with some extra padding text to make it longer for wrap testing purposes maybe
line three of the document with some extra padding text to make it longer for wrap testing purposes maybe
line four of the document with some extra padding text to make it longer for wrap testing purposes maybe
line five of the document with some extra padding text to make it longer for wrap testing purposes maybe")
qa_start "$file"
# Wait for the wrap indicator to render. Guarded with || true: under the
# helpers' `set -e`, an unguarded qa_expect timeout kills the whole script
# (exit 1, zero assertions run) instead of reaching the real assertion
# below — exactly how this script failed its first full `make qa` run.
qa_expect_screen "↪" 5 -F || true

# NOTE: .txt is one of the prose extensions that default word wrap ON
# (Preferences.pm WRAP_DEFAULT_EXTENSIONS: md/txt/rst/adoc/markdown/text),
# so wrap is already active for this file — no Alt+Z needed. (An earlier
# version of this test pressed Alt+Z here, which actually *turned wrap
# off* since it was already on by filetype default, and made this test
# flaky-looking. Verified via wrap_001_toggle.sh's pattern of reading
# actual state rather than assuming it.)
qa_assert_screen "↪" "word wrap is active by default for .txt files"

# Press inside the text area (row 5, well below the top), then drag UP past
# the top of the text viewport (row 2 = ruler, row 1 = tab bar) and release.
qa_mouse_press 10 5 0 0.1
qa_mouse_drag 10 4 0 0.1
qa_mouse_drag 10 2 0 0.1
qa_mouse_release 10 2 0 0.2

qa_assert_cursor_at "1:1" "drag above viewport clamps to document start"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
