#!/usr/bin/env bash
# QA-REG-178: Status bar with column-select indicator active must never
# overflow the terminal width.
#
# Bug (found via direct math on _render_context_status_bar, then
# confirmed live): the inline "COL n" / "COL n×m" indicator that appears
# while column-select mode (⌥C) is active was appended to the status
# bar's left segment UNCONDITIONALLY -- with no check for whether there
# was still room before the fixed-width "Commands ⌃␣" palette pill on
# the right. At narrow widths (e.g. 40 cols) with the indicator active,
# the assembled line could exceed $cols with nothing left to shrink,
# which the terminal then soft-wraps onto a phantom row -- scrolling and
# corrupting the whole screen (tab bar and ruler disappear). Fix: the COL
# indicator (like the multi-cursor indicator, QA-REG-179) is now gated
# behind the same budget check the rest of the bar respects, and is
# dropped entirely (not truncated mid-text) when it doesn't fit.
# See bugs.md 2026-08-30, qa/26_status_bar.txt QA-SBAR-022.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-178: Column-select status bar indicator never overflows"

# Portable printable-width check: strip ANSI escapes, measure character
# (not byte) length. Perl is a guaranteed dependency (CLAUDE.md).
line_width() {
    printf '%s' "$1" | perl -CSD -pe 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\x1b\[\?[0-9]+[hl]//g; chomp; $_ = length($_)."\n"'
}

content="foo bar foo baz foo qux"$'\n'
for i in $(seq 1 20); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "zdisc_check.demo.txt" "$content")
qa_start "$file"

for size in "80 24" "60 20" "50 18" "40 15"; do
    cols=${size% *}
    rows=${size#* }
    qa_resize_window "$cols" "$rows"
    sleep 0.3

    # Enter column mode and extend the selection both down AND right, to
    # build an actual rectangle -- this renders as "COL n×m", the longer
    # form. A vertical-only selection ("COL n", e.g. "COL 13") turns out
    # to stay just within budget even in the unpatched/buggy code at 40
    # cols (confirmed while writing this script: down-only alone did NOT
    # catch the regression -- it passed vacuously either way). The
    # rectangle form is what actually crosses the overflow threshold.
    qa_keys "alt-c"
    for _ in $(seq 1 12); do qa_keys "down"; done
    for _ in $(seq 1 5); do qa_keys "right"; done
    sleep 0.3
    qa_screen

    last_line=$(echo "$QA_SCREEN" | tail -1)
    w=$(line_width "$last_line")
    if [[ "$w" -le "$cols" ]]; then
        qa_pass "status bar fits at ${cols}x${rows} with column-select active (width=$w)"
    else
        qa_fail "status bar fits at ${cols}x${rows} with column-select active" "width=$w > cols=$cols: [$last_line]"
    fi

    # No scroll corruption: tab bar (row 1) must still show the filename.
    qa_assert_screen "zdisc_check" "tab bar intact at ${cols}x${rows} (no scroll corruption)"
    # Palette trigger must never drop (UI_GUIDELINES.md: never droppable).
    qa_assert_screen "Commands" "Commands palette pill still present at ${cols}x${rows}"

    # Exit column mode before resizing again.
    qa_keys "alt-c"
    sleep 0.2
done

qa_keys "ctrl-q"
qa_summary
