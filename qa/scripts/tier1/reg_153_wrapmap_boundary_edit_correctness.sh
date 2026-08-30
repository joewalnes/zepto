#!/usr/bin/env bash
# QA-REG-153: WrapMap stays correct far from a wrap-boundary-crossing edit
#
# Regression test for bugs.md P3 "WrapMap::invalidate_line() has an
# O(remaining-lines) tail on wrap-boundary changes". The fix replaced the
# O(remaining-lines) walk that keeps per-line visual-row offsets correct
# with a Fenwick tree (O(log n) point update / query). This test does not
# assert anything about speed — it asserts CORRECTNESS: that after an edit
# near the top of a large wrapped file changes that line's wrapped-segment
# count (a "wrap-boundary-crossing" edit, delta != 0), a line hundreds of
# rows away still renders at the correct position. A botched offset-tracking
# fix would show up here as misaligned gutter numbers / wrong content far
# from the edit point, not as a crash.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-153: WrapMap boundary-edit correctness at distance"

# 300 lines, each long enough to wrap into 2 segments in virtually any
# terminal width, each carrying a unique marker so we can identify it
# unambiguously on screen after scrolling.
content=""
for i in $(seq 0 299); do
    content+="Marker${i}Start this is a long padding line of repeated words word word word word word word word word word word word word word word word word word word word word MarkerEnd${i}"
    content+=$'\n'
done
file=$(qa_tmpfile "reg153.txt" "$content")
qa_start "$file"

# Ensure word wrap is ON. Default word-wrap state varies (has been observed
# ON by default even for .txt in this build), so check for the wrap
# continuation marker rather than assuming a blind single alt-z toggle
# lands in the right state either way.
qa_screen
if ! echo "$QA_SCREEN" | grep -q '↪'; then
    qa_keys "alt-z"
    sleep 0.3
fi
qa_assert_screen "↪" "word wrap is active (continuation marker visible)"
qa_assert_screen "Marker0Start" "file loaded, line 0 visible"

# Jump to line 6 (near the top, but deliberately NOT line 1 -- line index 0
# is a Fenwick-tree degenerate case where an off-by-one indexing bug happens
# to be masked by tree-node overlap; line index 5 is not) and grow it so it
# gains an extra wrapped segment (delta = +1) -- this is the
# wrap-boundary-crossing edit that used to trigger the O(remaining-lines)
# walk.
# (Note: "goto line" footer input needs an explicit Enter key after typing
# the number -- observed interactively that qa_sendline's trailing newline
# alone does not submit this particular input widget.)
qa_keys "ctrl-g" 0.2
qa_send "6" 0.2
qa_keys "enter" 0.3
qa_send "EXTRA_TEXT_TO_FORCE_A_NEW_WRAP_SEGMENT_TO_APPEAR_RIGHT_HERE_NOW " 0.2
sleep 0.3

# Jump far away (line 250, ~248 lines past the edit) and verify BOTH the
# gutter number and the unique content marker line up correctly. This is
# the assertion that would catch a broken offset-tracking scheme: wrong
# offsets manifest as misalignment between the requested line and what's
# actually shown, not a crash.
qa_keys "ctrl-g" 0.2
qa_send "250" 0.2
qa_keys "enter" 0.3

qa_assert_cursor_at "250" "cursor lands exactly on requested line 250"
qa_assert_screen "Marker249Start" "correct content (0-indexed line 249) shown at distance from the edit"

# Also verify a line immediately adjacent to the far target, to catch an
# off-by-one in the offset tracking specifically (not just gross corruption).
qa_keys "ctrl-g" 0.2
qa_send "251" 0.2
qa_keys "enter" 0.3
qa_assert_screen "Marker250Start" "adjacent line 251 (0-indexed 250) also correctly aligned"

# And confirm the editor is still alive and well after all this (sanity net).
if qa_alive; then
    qa_pass "editor still running after boundary-crossing edit + long-distance navigation"
else
    qa_fail "editor crashed"
fi

qa_keys "ctrl-q"
qa_summary
