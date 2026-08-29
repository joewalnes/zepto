#!/usr/bin/env bash
# QA-MS-022: Hovering a bright status bar pill brightens it (never dims)
# Bug: pill_hover_bg was dimmer than the toggle-on/palette pill colors, so
# hovering those pills DE-highlighted them (looked like a stale render).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MS-022: Pill hover brightens (visual)"

file=$(qa_tmpfile_nl "ms022.txt" $'alpha\nbeta\ngamma')
qa_start "$file"
sleep 0.5

# Locate the Word Wrap pill (a toggle pill; ON by default → bright blue)
qa_screen
row=$(echo "$QA_SCREEN" | wc -l | tr -d ' ')
line=$(echo "$QA_SCREEN" | grep -n "Word Wrap" | head -1 | cut -d: -f1)
if [[ -z "$line" ]]; then
    qa_skip "Word Wrap pill not on status bar at this width"
    qa_keys "ctrl-q"
    qa_summary
    exit 0
fi
# Character-based column (grep -bo gives BYTE offsets, which overshoot when
# multi-byte icons precede the label on the status bar)
linetext=$(echo "$QA_SCREEN" | sed -n "${line}p")
prefix="${linetext%%Word Wrap*}"
col=${#prefix}

before="$QA_TMPDIR/ms022_before.png"
after="$QA_TMPDIR/ms022_after.png"
qa_screenshot "$before"

# Hover over the pill (motion, no click)
qa_hover "$((col + 4))" "$line"
sleep 0.5
qa_screenshot "$after"

# Deterministic sanity: hover changed the rendering at all
if ! cmp -s "$before" "$after"; then
    qa_pass "hover motion over pill changed the rendered frame"
else
    qa_fail "hover motion over pill did not change the rendered frame"
fi

qa_assert_visual "$after" \
    "This shows a TUI text editor. On the bottom status bar there is a pill-shaped button labeled 'Word Wrap' which the mouse is hovering over. Verify: the Word Wrap pill background is BRIGHTER / more vivid than the other pills on the status bar (a light bright blue). It must NOT look dimmer, grayer, or more muted than the 'Open' and 'Commands' pills." \
    "hovered pill is brighter than its neighbors, not dimmer"

qa_keys "ctrl-q"
qa_summary
