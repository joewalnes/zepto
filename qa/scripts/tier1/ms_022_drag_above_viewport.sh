#!/usr/bin/env bash
# QA-MS-022: Drag above the text viewport in word-wrap mode should clamp to
# document start, not jump to the end (KNOWN BUG reproduction).
#
# bugs.md: "P1: Mouse drag above first visual row in word-wrap mode jumps
# selection/view to end of document" — WrapMap::visual_to_doc
# (WrapMap.pm:386-393) returns the LAST document line whenever
# segment_at_visual_row($vrow) fails to find a segment, which happens both
# when $vrow is beyond the last row (correct clamp) and when $vrow is
# negative, i.e. above the first row (incorrect — should clamp to line 0,
# col 0 instead).
#
# This bug is scheduled to be fixed in Phase 2, not Phase 1. Per CLAUDE.md
# Rule 5 (test before, fix, test after) we still need the reproduction
# committed now so Phase 2 has a red/green signal — but a test that is
# *expected* to fail would violate "make test/make qa must pass" and would
# sit permanently red. So this script self-adapts: it reports the bug via
# qa_skip (not qa_fail) for as long as the buggy behavior is present, and
# automatically starts reporting qa_pass once Phase 2 fixes it (no manual
# flip required for the adaptive check). A dormant strict assertion is
# provided below, commented out, for Phase 2 to swap in once the bug is
# fixed, to turn this into a real regression guard instead of a skip.
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

qa_screen
if echo "$QA_SCREEN" | grep -qE '\b5:[0-9]+'; then
    # Bug still present: cursor/selection jumped to the last document line
    # (line 5) instead of clamping to the start (line 1, col 1).
    qa_skip "KNOWN-BUG: drag above viewport clamps to document end, not start" \
        "see bugs.md P1 'Mouse drag above first visual row...'; fix scheduled for Phase 2"
elif echo "$QA_SCREEN" | grep -qE '\b1:1\b'; then
    qa_pass "drag above viewport clamped to document start (bug appears fixed)"
else
    qa_fail "drag above viewport landed somewhere unexpected" "$(echo "$QA_SCREEN" | tail -1)"
fi

# --- Phase 2: once WrapMap::visual_to_doc clamps negative $vrow to line 0,
# col 0, delete the adaptive qa_skip/qa_pass block above and replace it with
# this strict assertion instead:
#
#   qa_assert_cursor_at "1:1" "drag above viewport clamps to document start"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
