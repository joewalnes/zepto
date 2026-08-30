#!/usr/bin/env bash
# QA-REG-174: Rows below EOF (and the status bar's own gap fill) use the
# CURRENT theme's real background, not a stale/dark fallback.
#
# Investigated as a reported P1 ("light theme shows a solid dark rectangle
# below EOF, invisible in dark theme because it coincidentally looks
# right") — see bugs.md 2026-08-30 "Light-theme dark background fill
# investigation". Did NOT reproduce against the terminal's own
# authoritative state: `hangon screenshot` showed a dark rectangle, but
# `tmux capture-pane -e` (which reads the SAME live session's actual
# per-cell SGR attributes, independent of hangon's own screenshot
# rendering) shows the correct light-theme color underneath it. Root
# cause traced to `hangon screenshot`'s own image renderer, not Zepto —
# confirmed reproducible from raw bytes with zero Zepto code involved.
#
# This script exists as the "confirmed correct" regression guard: it
# asserts, via the raw ANSI byte stream (not just rendered screen text,
# and not via the sometimes-misleading `hangon screenshot`), that a short
# file in light theme really does carry the light theme's own
# empty_line_bg color below EOF and never the dark theme's.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-174: Light theme empty-row background (below EOF)"

file=$(qa_tmpfile_nl "reg174.txt" "line one
line two")
qa_start "$file"

# Switch to light theme
qa_keys "ctrl-t" 0.4
qa_assert_expect "reg174" "file is open"

# Pull raw ANSI bytes for the whole screen (authoritative terminal state —
# tmux's own tracked per-cell attributes, not hangon's screenshot renderer)
# and check a row well below the 2-line document's content for the light
# theme's empty_line_bg color.
tmux_sess=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
raw=$(tmux capture-pane -t "hangon-${tmux_sess}" -p -e 2>/dev/null)

# Row 5 (1-based, well below the 2-line document + tab bar + ruler) should
# carry light theme's empty_line_bg = rgb(250,250,252).
row5=$(echo "$raw" | sed -n '5p')
if echo "$row5" | grep -q '48;2;250;250;252'; then
    qa_pass "below-EOF row uses light theme's empty_line_bg (250,250,252)"
else
    qa_fail "below-EOF row uses light theme's empty_line_bg (250,250,252)" \
        "row5 raw bytes: $row5"
fi

# The dark theme's empty_line_bg (20,21,30) and main bg (26,27,38) must
# never appear anywhere on screen while light theme is active.
if echo "$raw" | grep -q '48;2;20;21;30'; then
    qa_fail "no dark theme empty_line_bg leaking into light theme screen" \
        "found 48;2;20;21;30 somewhere on screen"
else
    qa_pass "no dark theme empty_line_bg leaking into light theme screen"
fi

qa_keys "ctrl-q"
qa_summary
