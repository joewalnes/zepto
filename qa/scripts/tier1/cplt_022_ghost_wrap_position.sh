#!/usr/bin/env bash
# QA-CPLT-022: Ghost completion renders at the cursor on wrapped lines
#
# bugs.md P2 "Ghost completion renders offset from cursor in
# wrapped/markdown lines": Renderer.pm's ghost-render branch guarded on
# !$is_wrap_cont, so the ghost suggestion always rendered on the line's
# FIRST visual segment regardless of which wrap segment the cursor was
# actually on. Fixed in Phase 2: the branch now checks whether the
# cursor's document column falls within THIS row's wrap segment range.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-022: Ghost completion position on wrapped lines"

# Screen layout: row 1 = tab bar, row 2 = ruler, row 3 = doc line 1,
# row 4 = doc line 2 segment 0 (first visual row), row 5 = doc line 2's
# wrap continuation (where the cursor — and thus the ghost — actually is).
#
# Line 1 seeds "myUniqueWordToken" as a known word. Line 2 is typed so it
# wraps into exactly two visual segments, ending in a short partial prefix
# ("myU") that word-completes against line 1's word — landing the cursor
# (and the ghost) on the CONTINUATION row, not the first segment.
# .txt is one of the prose extensions that default word wrap ON
# (Preferences.pm WRAP_DEFAULT_EXTENSIONS) — no Alt+Z needed.
file=$(qa_tmpfile_nl "cplt022.txt" "myUniqueWordToken here
")
qa_start "$file"
qa_expect_screen "myUniqueWordToken" 5 -F || true

qa_keys "down"
qa_keys "end"
qa_send "some filler text to force wrapping across multiple visual rows here yes myU" 1.0
qa_expect_screen "↪" 5 -F || true

qa_screen
row4=$(printf '%s' "$QA_SCREEN" | sed -n '4p')
row5=$(printf '%s' "$QA_SCREEN" | sed -n '5p')

if [[ "$row4" != *"myUniqueWordToken"* ]]; then
    qa_pass "ghost suggestion does NOT leak onto wrap segment 0"
else
    qa_fail "ghost suggestion incorrectly rendered on segment 0" "$row4"
fi

if [[ "$row5" == *"myUniqueWordToken"* ]]; then
    qa_pass "ghost suggestion renders on the continuation row containing the cursor"
else
    qa_fail "ghost suggestion missing from the row containing the cursor" "$row5"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
