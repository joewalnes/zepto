#!/usr/bin/env bash
# QA-THM-012: Cross-instance theme sync — idle window repaints without input
#
# bugs.md item 4 "Cross-instance theme sync": StateStore::check_for_changes()
# was previously only called inside render(), so an IDLE instance (not
# typing, therefore not re-rendering) never noticed another window's theme
# change. Fixed via Editor::_poll_cross_instance_prefs, called from the
# main loop's idle-timeout branch.
#
# This test drives two independent hangon sessions sharing a state
# directory, toggles the theme in one, and asserts the OTHER repaints
# on its own — verified via raw ANSI color capture (qa_raw_screen), since
# text content is identical between themes and wouldn't catch a real
# regression here.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-THM-012: Cross-instance theme sync while idle"

# Manual two-session setup — qa_start() only manages a single $QA_SESSION,
# so this test drives hangon directly for both sessions.
STATE_DIR="$QA_TMPDIR/shared_theme_state"
mkdir -p "$STATE_DIR"
file_a=$(qa_tmpfile_nl "thm012_a.txt" "instance A content")
file_b=$(qa_tmpfile_nl "thm012_b.txt" "instance B content")

SESSION_A="thm012_a_$$"
SESSION_B="thm012_b_$$"
cleanup() {
    hangon stop "$SESSION_A" >/dev/null 2>&1 || true
    hangon stop "$SESSION_B" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hangon start process --name "$SESSION_A" -- "$QA_ZEPTO" --state-dir "$STATE_DIR" "$file_a" >/dev/null
hangon start process --name "$SESSION_B" -- "$QA_ZEPTO" --state-dir "$STATE_DIR" "$file_b" >/dev/null
sleep 1

qa_raw_screen "$SESSION_B"
before_screen="$QA_RAW_SCREEN"

if [[ -z "$before_screen" ]]; then
    qa_fail "could not capture instance B's raw screen (tmux target lookup failed)" ""
else
    # Toggle theme in A only — never touch B.
    hangon keys "$SESSION_A" "ctrl-t"

    # Wait ~2s WITHOUT sending B any input, then capture its raw screen.
    sleep 2
    qa_raw_screen "$SESSION_B"
    after_screen="$QA_RAW_SCREEN"

    if [[ "$after_screen" != "$before_screen" ]]; then
        qa_pass "instance B's rendered colors changed without receiving any input"
    else
        qa_fail "instance B's screen is identical before/after — cross-instance sync did not repaint it" \
            "(compared raw ANSI capture, not just text)"
    fi

    # Cross-check against instance A's own (input-driven) repaint, to
    # confirm both ended up on the SAME theme, not just "some" difference.
    qa_raw_screen "$SESSION_A"
    a_screen="$QA_RAW_SCREEN"

    # Extract the tab-bar background color escape sequence (first
    # `48;2;R;G;B` truecolor background found) from each capture and
    # compare them.
    extract_bg() {
        printf '%s' "$1" | grep -oE '48;2;[0-9]+;[0-9]+;[0-9]+' | head -1 || true
    }
    a_bg=$(extract_bg "$a_screen")
    b_bg=$(extract_bg "$after_screen")

    if [[ -n "$a_bg" && "$a_bg" == "$b_bg" ]]; then
        qa_pass "instance B converged to the SAME theme color as instance A ($a_bg)"
    else
        qa_fail "instance B's theme color does not match instance A after sync" \
            "A=$a_bg B=$b_bg"
    fi
fi

hangon keys "$SESSION_A" "ctrl-q"
sleep 0.2
hangon send "$SESSION_A" "n" >/dev/null 2>&1 || true
hangon keys "$SESSION_B" "ctrl-q"
sleep 0.2
hangon send "$SESSION_B" "n" >/dev/null 2>&1 || true

qa_summary
