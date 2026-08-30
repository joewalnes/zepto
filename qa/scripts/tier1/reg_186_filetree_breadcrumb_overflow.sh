#!/usr/bin/env bash
# QA-REG-186: FILE_TREE-context hint row's breadcrumb (cursor node path)
# must never, combined with the fixed Open/Commands pills, overflow the
# terminal width.
#
# Confirmed via direct PNG screenshot inspection (not an LLM guess):
# opening the file tree at 40x15 and navigating to an entry with a
# realistic path (e.g. a project directory's own dotfiles/subdirs) pushed
# the assembled hint row past 40 columns. The terminal soft-wrapped the
# overflow onto a phantom row, scrolling the tab bar/ruler out of view --
# the exact same failure class QA-REG-179 fixed for the DOCUMENT-context
# status bar's multi-cursor indicator, but here the breadcrumb path itself
# was pushed unconditionally, with no truncation, before the fixed-width
# Open/Commands pills' width was ever accounted for.
#
# Fix: the breadcrumb is now ellipsized (from the start, keeping the
# filename tail visible) against whatever room is left after the fixed
# right-side pills, and drops to empty rather than negative-width if
# there's truly no room. See tests/renderer.t for the exhaustive
# combinatorial proof (all nerd-font/width/path-length combinations); this
# script is the live/interactive confirmation.
# See bugs.md 2026-08-30, qa/22_file_tree.txt.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-186: FILE_TREE breadcrumb never overflows the hint row"

# NOTE: a terminal's soft-wrap can never itself produce a captured line
# WIDER than the terminal's column count -- by definition, wrapping is
# what splits an overlong line into pieces each <= cols. So measuring
# "is the last captured line <= cols" is NOT a valid signal (it always
# passes, even on the broken binary -- confirmed while writing this
# script). The real, observable symptom is different: when the status
# bar's fixed-position write emits more bytes than the terminal is wide,
# the terminal wraps onto a new row that doesn't exist within the
# window's fixed height, so it SCROLLS the whole screen up by one line --
# pushing row 1 (the tab bar, which should always be the very first
# captured line) off the top entirely. That's what this script checks
# for directly: is the tab bar's own marker (the untitled-tab bracket)
# still present on the FIRST captured line, or has it scrolled away.

# A project dir whose own top-level entries include a realistic,
# non-trivial dotfile name -- exactly the shape that reproduced the bug.
dir="$QA_TMPDIR/reg186_proj"
mkdir -p "$dir/.claude"
echo "content" > "$dir/notes.txt"

qa_start "$dir"
# Launching on a directory focuses the tree by default -- no ctrl-b needed
# (and pressing it here would toggle the tree CLOSED instead of opening it).
qa_resize_window 40 15
sleep 0.3

qa_screen
first_line=$(echo "$QA_SCREEN" | head -1)
if [[ "$first_line" == *"untitled"* ]]; then
    qa_pass "tab bar (row 1) still visible -- no scroll corruption from status bar overflow"
else
    qa_fail "tab bar (row 1) still visible" "tab bar marker missing from row 1 (screen scrolled): [$first_line]"
fi

# Also confirm the Commands pill (Discoverability Contract's unconditional
# fallback signpost) is actually somewhere on screen, not lost entirely.
if [[ "$QA_SCREEN" == *"Commands"* ]]; then
    qa_pass "Commands pill still visible somewhere on screen"
else
    qa_fail "Commands pill still visible somewhere on screen" "not found anywhere in captured screen"
fi

qa_keys "ctrl-q" 0.3
qa_stop
qa_summary
