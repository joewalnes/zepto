#!/usr/bin/env bash
# QA-TERM-015: Rendering-glitch sweep — catches transient visual corruption
# during/right-after realistic editing operations.
#
# WHY "during/right after", not resting states: visual corruption (stale
# duplicate text, misaligned gutter/ruler, garbled box-drawing, a redraw
# that only partially completed) tends to show up transiently mid-action,
# then often self-corrects on the next full repaint. A screenshot taken
# after a generous settle sleep — the pattern every other tier2 script in
# this suite uses on purpose, because they're testing STEADY-STATE
# discoverability/rendering — would systematically miss exactly the class
# of bug this sweep exists to catch. So every case below sends input with
# little or no settle delay (`qa_send "..." 0` / `qa_keys "..." 0`,
# sometimes chained rapidly) and screenshots immediately, on purpose. This
# is deliberately the opposite instinct from most QA scripts in this repo.
#
# Uses a single broad "does anything here look visually broken" vision
# prompt rather than a specific assertion — this is intentionally a
# catch-all. You don't know what glitch you're looking for in advance;
# that's the whole point of a sweep like this. Contrast with
# reg_165_ghost_completion_self_match_render.sh, which asserts one
# SPECIFIC, already-diagnosed on-screen string.
#
# ===========================================================================
# TRUST BUT VERIFY — DO NOT SKIP THIS STEP
# ===========================================================================
# This vision model is NOT reliable at pixel-level rendering claims. In an
# earlier sweep of this same pipeline (discoverability_sweep.sh, see
# bugs.md's "Calibration note" under the QA-DISC-001 entry, 2026-08-30),
# the model hallucinated 2 false positives out of 8 real screenshots when
# asked about concrete visual-defect claims: a ruler/gutter "line number
# duplication" that, on direct re-inspection of the actual screenshot, was
# never there (it had conflated a legitimate distinct UI element with the
# gutter), and a "corner hint overlap" that also didn't reproduce on
# direct re-capture. Both were judgment-sounding, specific, and wrong.
#
# So: for every FAIL this script produces, before writing it into bugs.md
# as a real bug —
#   1. Re-run JUST that scenario (the case functions below are individually
#      re-runnable; see comments at each call site for the exact repro
#      steps, or re-run this whole script with QA_TEST_NAME set to isolate
#      output).
#   2. Open the saved screenshot yourself (the PNG path is printed in the
#      FAIL detail / left in $QA_TMPDIR — Read tool or `open`/`xdg-open` it)
#      and look at the specific pixels the model complained about.
#   3. Only log it in bugs.md if you can see the defect yourself.
# A FAIL from this script is a lead, not a confirmed bug. Never paste the
# model's FAIL reason into bugs.md verbatim without having looked.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-TERM-015: Rendering glitch sweep (mid-operation screenshots)"

if ! qa_llm_available; then
    qa_skip "rendering glitch sweep" "LLM not configured (set ANTHROPIC_API_KEY or ZEPTO_QA_API_KEY)"
    qa_summary
    exit 0
fi

GLITCH_PROMPT='You are inspecting a screenshot of a terminal text editor (Zepto), captured deliberately mid-operation or immediately after one (typing, undo/redo, a tab switch, a wrap toggle, a terminal resize, a scroll, or a completion popup opening/closing) -- so a moment of legitimate transient state (e.g. a completion dropdown that is SUPPOSED to be open, normal syntax-highlight colors, the cursor blinking) is expected and is NOT a bug. Look ONLY at this screenshot for actual rendering DEFECTS: duplicated text that should not be duplicated, misaligned gutter/line-number/ruler columns, garbled or overlapping characters, a broken box-drawing border, a UI element that is visibly cut off/truncated where it should not be, content that looks like it belongs to a different file/tab than what is shown, or any other corruption a careful human would call "visually broken". Reply PASS if the screen looks visually correct and uncorrupted for whatever state it is in. Reply FAIL: <precise description of exactly what looks broken and where on screen> otherwise. Be specific -- vague claims are not useful.'

# perl instead of python3: python3 is not in this repo's documented QA
# dependency list (Perl, prove, hangon, tmux, git — see CLAUDE.md), so a
# script that shells out to it would silently break on a minimal runner.
long_line() { perl -e 'print "word${1} " x 60' -- "${1:-}"; }

shoot() {
    local label="$1"
    local shot="$QA_TMPDIR/glitch_${label}.png"
    qa_screenshot "$shot"
    qa_assert_visual "$shot" "$GLITCH_PROMPT" "$label"
}

# --- 1. Typing into the middle of existing text -----------------------
# Repro: open a file, jump to the middle of a line, type more text with
# no settle delay, screenshot immediately (before the post-type render
# has had a chance to fully "cool down").
case_mid_word_typing() {
    local file
    file=$(qa_tmpfile_nl "glitch_mid.txt" "the quick brown fox jumps over the lazy dog
second line of unrelated content
third line also unrelated")
    qa_start "$file"
    qa_keys "down" 0
    qa_keys "home" 0
    for _ in $(seq 1 16); do qa_keys "right" 0; done   # land mid "jumps"
    qa_send "REALLYLONGINSERT" 0
    shoot "mid_word_typing"
    qa_stop
}

# --- 2. Undo/redo sequences --------------------------------------------
# Repro: type several edits, then fire a rapid undo/undo/redo burst with
# no settle delay, screenshotting after the burst (still very close to
# the last undo/redo repaint).
case_undo_redo_burst() {
    local file
    file=$(qa_tmpfile_nl "glitch_undo.txt" "line one
line two
line three")
    qa_start "$file"
    qa_raw $'\x1b[1;5F' 0   # Ctrl+End (CSI 1;5F) -- hangon has no ctrl-end key name
    qa_send " alpha" 0
    qa_send " beta" 0
    qa_send " gamma" 0
    qa_keys "ctrl-z" 0
    qa_keys "ctrl-z" 0
    qa_keys "ctrl-y" 0
    shoot "undo_redo_burst"
    qa_stop
}

# --- 3. Toggling word wrap on a wrapped file ---------------------------
# Repro: many long lines (guarantees multi-segment wrapping), toggle wrap
# on, screenshot immediately -- this is the exact subsystem (WrapMap /
# ghost-text interplay) that produced the real self-match ghost-text bug
# (bugs.md, QA-REG-165), so it's a high-value spot to keep sweeping even
# though that specific bug is fixed.
case_wrap_toggle() {
    local content=""
    for i in $(seq 1 20); do content+="$(long_line "$i")"$'\n'; done
    local file
    # .dat, not .txt: Preferences.pm's WRAP_DEFAULT_EXTENSIONS defaults
    # wrap to ON for .txt/.md/etc, which would make the first alt-z below
    # turn wrap OFF instead of on (found while validating perf_020, the
    # sibling perf script that hit this same extension trap).
    file=$(qa_tmpfile_nl "glitch_wrap.dat" "$content")
    qa_start "$file"
    qa_keys "right" 0.1   # warm-up: a bare Alt-chord as the literal first
                          # keystroke after startup can be silently dropped
                          # (bugs.md, "First Alt-chord after startup can be
                          # silently dropped", open P2) -- a plain key first
                          # avoids flaking on that unrelated, already-known bug
    qa_keys "alt-z" 0
    shoot "wrap_toggle_on"
    qa_keys "alt-z" 0
    qa_stop
}

# --- 4. Switching tabs rapidly ------------------------------------------
# Repro: 4 tabs with visually distinct content, alt-. spammed with no
# settle delay between presses, screenshot right after the burst.
case_rapid_tab_switch() {
    local f1 f2 f3 f4
    f1=$(qa_tmpfile_nl "glitch_tab1.txt" "TAB_ONE_MARKER
aaaaaaaaaaaaaaaaaaaaaaaa")
    f2=$(qa_tmpfile_nl "glitch_tab2.txt" "TAB_TWO_MARKER
bbbbbbbbbbbbbbbbbbbbbbbb")
    f3=$(qa_tmpfile_nl "glitch_tab3.txt" "TAB_THREE_MARKER
cccccccccccccccccccccccc")
    f4=$(qa_tmpfile_nl "glitch_tab4.txt" "TAB_FOUR_MARKER
dddddddddddddddddddddddd")
    qa_start "$f1" "$f2" "$f3" "$f4"
    qa_keys "right" 0.1   # warm-up, see the wrap-toggle case's comment above
    for _ in $(seq 1 6); do qa_keys "alt-." 0; done
    shoot "rapid_tab_switch_forward"
    for _ in $(seq 1 3); do qa_keys "alt-," 0; done
    shoot "rapid_tab_switch_backward"
    qa_stop
}

# --- 5. Opening/dismissing the completion popup -------------------------
# Repro: type a 2+ char word prefix that has real candidates (auto-trigger
# fires after a short debounce), screenshot while the popup should be up,
# then Escape it and screenshot again immediately.
case_completion_popup() {
    local file
    file=$(qa_tmpfile_nl "glitch_cplt.js" "const longVariableNameOne = 1
const longVariableNameTwo = 2
")
    qa_start "$file"
    qa_raw $'\x1b[1;5F' 0   # Ctrl+End (CSI 1;5F) -- hangon has no ctrl-end key name
    qa_send "long" 0.3   # small pause: real debounce needs to actually fire
    shoot "completion_popup_open"
    qa_keys "escape" 0
    shoot "completion_popup_dismissed"
    qa_stop
}

# --- 6. Opening/closing the file tree ------------------------------------
# Repro: rapid ctrl-b toggles (open/close/open) with no settle delay.
case_tree_toggle() {
    local file
    file=$(qa_tmpfile_nl "glitch_tree.txt" "tree toggle content")
    qa_start "$file"
    qa_keys "ctrl-b" 0
    qa_keys "ctrl-b" 0
    qa_keys "ctrl-b" 0
    shoot "rapid_tree_toggle"
    qa_stop
}

# --- 7. Resizing the terminal mid-edit -----------------------------------
# Repro: start typing, then resize the tmux window (via the shared
# qa_resize_window helper — same mechanism discoverability_sweep.sh uses)
# right in the middle of it, screenshot immediately after the resize
# before giving the renderer a generous settle window.
case_resize_mid_edit() {
    local file
    file=$(qa_tmpfile_nl "glitch_resize.txt" "line before resize
another line here
and one more for good measure")
    qa_start "$file"
    qa_raw $'\x1b[1;5F' 0   # Ctrl+End (CSI 1;5F) -- hangon has no ctrl-end key name
    qa_send "typing when resize hits" 0
    qa_resize_window 60 18
    shoot "resize_mid_edit_narrow"
    qa_resize_window 100 30
    shoot "resize_mid_edit_wide"
    qa_stop
}

# --- 8. Scrolling through a large file -----------------------------------
# Repro: a large file, a rapid pagedown burst with no settle delay,
# screenshot right after — this is exactly the kind of large-file
# scroll/render path where WrapMap/Renderer incremental-update bugs have
# historically hidden (see bugs.md's WrapMap Fenwick-tree fix writeup).
case_rapid_scroll() {
    local content=""
    for i in $(seq 1 3000); do content+="scrollmarker line ${i} of content here"$'\n'; done
    local file
    file=$(qa_tmpfile_nl "glitch_scroll.txt" "$content")
    qa_start "$file"
    for _ in $(seq 1 8); do qa_keys "pagedown" 0; done
    shoot "rapid_scroll_down"
    for _ in $(seq 1 4); do qa_keys "pageup" 0; done
    shoot "rapid_scroll_up"
    qa_stop
}

case_mid_word_typing
case_undo_redo_burst
case_wrap_toggle
case_rapid_tab_switch
case_completion_popup
case_tree_toggle
case_resize_mid_edit
case_rapid_scroll

qa_summary
