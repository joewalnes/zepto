#!/usr/bin/env bash
# QA-THM-004: Tab bar updates on theme switch (no stale dark tabs)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-THM-004: Tab bar updates on theme switch (visual)"

f1=$(qa_tmpfile_nl "thm004_a.txt" "file one content")
f2=$(qa_tmpfile_nl "thm004_b.txt" "file two content")
qa_start "$f1" "$f2"

# Toggle to light theme
qa_keys "ctrl-t"
sleep 0.3

shot="$QA_TMPDIR/thm004.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor in LIGHT theme with 2 tabs at the top. Verify: (1) The TAB BAR at the top has a LIGHT background — not dark. (2) The tab text is dark/readable on the light background. (3) No stale dark-colored tabs remain — all tabs match the light theme." \
    "Tab bar renders in light theme colors after toggle"

qa_keys "ctrl-t"
qa_keys "ctrl-q"

qa_summary
