#!/usr/bin/env bash
# QA-REG-179: Status bar with the multi-cursor indicator active must
# never overflow the terminal width -- this is the bug that was actually
# caught via direct PNG screenshot inspection (real, confirmed screen
# corruption, not an LLM guess).
#
# Repro that found it: open a realistic-length filename (~15-20 chars,
# NOT a trivial 3-char name) at 40x15 with the file tree closed, then
# grow the multi-cursor count (⌃D "select next occurrence" a handful of
# times). The persistent "N cursors" indicator was appended to the
# status bar's left segment unconditionally, same defect class as the
# column-select indicator (QA-REG-178): no check against the fixed-width
# "Commands ⌃␣" palette pill before emitting it. Once the assembled line
# exceeded 40 columns, the terminal soft-wrapped the overflow onto a
# phantom row -- an actual terminal scroll the app's fixed-position
# redraw didn't account for, so the tab bar and ruler vanished from view
# and a bare, unstyled fragment (e.g. "8 cursors") appeared at the
# bottom, overlapping what should have been document content. This is
# the same CLASS of bug the QA-REG-126 message-truncation fix handles
# for transient messages, but that fix doesn't cover this persistent
# pill content. Fix: the multi-cursor indicator is now gated behind the
# same budget the rest of the bar respects (dropped, not truncated, when
# it doesn't fit), and the cursor-position pill itself is ellipsized as
# a last-resort backstop for pathological cases (see tests/renderer.t
# property sweep for the exhaustive combinatorial proof -- this script
# is the live/interactive confirmation).
# See bugs.md 2026-08-30, qa/26_status_bar.txt QA-SBAR-022.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-179: Multi-cursor status bar indicator never overflows"

line_width() {
    printf '%s' "$1" | perl -CSD -pe 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\x1b\[\?[0-9]+[hl]//g; chomp; $_ = length($_)."\n"'
}

# Realistic filename (not 3 chars) with several repeats of "foo" so ⌃D
# ("select next occurrence") can grow the cursor count into double digits.
content=$'foo bar foo baz foo qux foo zap foo end foo more foo extra foo tail\nline two\nline three\n'
file=$(qa_tmpfile_nl "zdisc_check.demo.txt" "$content")
qa_start "$file"
qa_resize_window 40 15
sleep 0.3

# Baseline: confirm no overflow before doing anything (the literal repro
# from the bug report -- realistic filename, tree closed, 40x15).
qa_screen
last_line=$(echo "$QA_SCREEN" | tail -1)
w=$(line_width "$last_line")
if [[ "$w" -le 40 ]]; then
    qa_pass "baseline status bar fits at 40x15 (width=$w)"
else
    qa_fail "baseline status bar fits at 40x15" "width=$w > 40: [$last_line]"
fi
qa_assert_screen "zdisc_check" "tab bar shows filename at baseline"

# Grow multi-cursor count and check after EVERY keystroke that the
# screen never scrolls/corrupts -- the original bug manifested as the
# tab bar disappearing partway through a sequence like this.
#
# IMPORTANT: each ⌃D also fires a transient "N cursors" confirmation
# message (Editor::Commands::cmd_select_next_occurrence ->
# show_message), which takes over the WHOLE status bar via
# _render_context_status_bar's early-return message branch -- already
# correctly bounded (QA-REG-126) and NOT the bug this script targets.
# That branch masks the PERSISTENT multi-cursor pill underneath, so a
# script that only presses ⌃D repeatedly never actually observes the
# pill and would tautologically "pass" even against the unpatched code
# (confirmed while writing this script: reverting the Renderer.pm fix
# and re-running with only the ⌃D loop below still passed). Typing a
# character clears the message (Editor.pm: "Clear on any user input")
# WITHOUT clearing multi-cursor mode, which is what actually surfaces
# the persistent "N cursors" pill this bug lives in.
overflow_seen=0
scroll_seen=0
for i in 1 2 3 4 5; do
    qa_keys "ctrl-d"
    sleep 0.2
    qa_screen
    last_line=$(echo "$QA_SCREEN" | tail -1)
    w=$(line_width "$last_line")
    if [[ "$w" -gt 40 ]]; then
        overflow_seen=1
        echo "       overflow after ctrl-d #$i: width=$w [$last_line]"
    fi
    if ! echo "$QA_SCREEN" | head -1 | grep -q "zdisc_check"; then
        scroll_seen=1
        echo "       tab bar missing after ctrl-d #$i (scroll corruption)"
    fi
done

# Dismiss the transient message by typing -- this is the step that
# actually surfaces the persistent multi-cursor pill ("N cursors")
# rather than the already-safe transient message. At 40 cols there may
# not be enough room for the pill at all (it's supplementary, correctly
# dropped rather than forced to fit -- see the wider-width check below
# for confirmation it's not just silently vanishing everywhere), but it
# must never be allowed to overflow if it IS shown.
qa_send "Z"
sleep 0.3
qa_screen
last_line=$(echo "$QA_SCREEN" | tail -1)
w=$(line_width "$last_line")
if [[ "$w" -gt 40 ]]; then
    overflow_seen=1
    echo "       overflow after typing (persistent multi-cursor pill): width=$w [$last_line]"
fi
if ! echo "$QA_SCREEN" | head -1 | grep -q "zdisc_check"; then
    scroll_seen=1
    echo "       tab bar missing after typing (scroll corruption)"
fi

if [[ "$overflow_seen" -eq 0 ]]; then
    qa_pass "no status bar line ever exceeded 40 cols across ctrl-d + typing"
else
    qa_fail "no status bar line ever exceeded 40 cols across ctrl-d + typing" "see widths above"
fi

if [[ "$scroll_seen" -eq 0 ]]; then
    qa_pass "tab bar never disappeared (no scroll corruption) across ctrl-d + typing"
else
    qa_fail "tab bar never disappeared (no scroll corruption) across ctrl-d + typing" "see log above"
fi

# Non-vacuousness check: confirm the persistent multi-cursor pill is
# ACTUALLY reachable and visible (not just correctly-dropped everywhere,
# which would make the checks above pass trivially even on broken code).
# At a wider width there's room for it, so it must be both visible AND
# still bounded -- this is the width where the original bug's overflow
# math (cursor pill + "N cursors" + palette pill > cols) was tightest
# while still fitting the pill at all.
qa_resize_window 55 20
sleep 0.3
qa_keys "ctrl-d"
sleep 0.2
qa_send "Z"
sleep 0.3
qa_screen
qa_assert_screen 'cursors' "persistent multi-cursor pill ('N cursors') is visible at 55 cols (sanity check this test isn't vacuous)"
last_line=$(echo "$QA_SCREEN" | tail -1)
w=$(line_width "$last_line")
if [[ "$w" -le 55 ]]; then
    qa_pass "status bar with visible multi-cursor pill still fits at 55 cols (width=$w)"
else
    qa_fail "status bar with visible multi-cursor pill still fits at 55 cols" "width=$w > 55: [$last_line]"
fi

qa_keys "ctrl-q"
qa_summary
