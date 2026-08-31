#!/usr/bin/env bash
# QA-REG-214: StateStore::check_for_changes() is now debounced (~1/sec)
# but cross-instance preference sync still works correctly -- just less
# eagerly polled, not broken.
#
# Bug: bugs.md "Scorecard audit round 3" P2 "StateStore::check_for_changes()
# runs a stat() per category on every render (per keystroke), not ~1/sec
# as documented". StateStore.pm's own doc comment said "Call from event
# loop (~1/sec)", but the only caller (Editor::render(), which runs on
# essentially every keystroke) invoked it completely unconditionally, with
# zero throttling of its own -- the exact same "stat() on every render is
# wasteful" problem Editor::_check_external_file_changes() already fixed
# for itself three lines above, in the same render() method.
#
# Fix: check_for_changes() now debounces itself (CHECK_INTERVAL_SEC = 1.0),
# mirroring _check_external_file_changes()'s existing guard. The risk this
# script guards against: a debounce implemented wrong could either (a)
# never let a real cross-instance change through at all (a functional
# regression, not just a perf one), or (b) fail to debounce at all (no
# perf improvement, silently reverting the fix). This confirms cross-
# instance preference sync -- the one thing check_for_changes() actually
# exists to do -- still works end-to-end through two real zepto instances
# sharing one --state-dir, exactly like reg_106_session_isolation.sh's
# two-session pattern (which is the same underlying isolation mechanism,
# just testing the opposite property: shared-not-isolated on purpose here).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-REG-214: check_for_changes() debounce does not break cross-instance sync"

fileA=$(qa_tmpfile_nl "reg214a.js" $'\tMARKERTAB_A')
fileB=$(qa_tmpfile_nl "reg214b.js" $'\tMARKERTAB_B')

# Two independent zepto sessions sharing the SAME state dir -- this is what
# makes preference changes in one visible to the other via StateStore's
# on_change listener, which check_for_changes() drives.
hangon start process --name "${QA_SESSION}_a" -- "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard "$fileA"
hangon start process --name "${QA_SESSION}_b" -- "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard "$fileB"
sleep 0.8

# Returns the 0-indexed screen column of MARKER in the given session.
marker_col() {
    local session="$1" marker="$2"
    local screen line
    screen=$(hangon screen "$session" 2>/dev/null || echo "")
    line=$(echo "$screen" | grep -m1 "$marker" || true)
    echo "$line" | grep -bo "$marker" 2>/dev/null | head -1 | cut -d: -f1 || true
}

# Normalize both sessions to a known starting tab width (4) so this test
# doesn't depend on whatever pref happened to be on disk already.
set_tab_width() {
    local session="$1" width="$2"
    hangon keys "$session" "ctrl-space"; sleep 0.2
    hangon send "$session" "Tab Width"; sleep 0.2
    hangon keys "$session" "enter"; sleep 0.2
    hangon keys "$session" "ctrl-a"; sleep 0.1
    hangon send "$session" "$width"; sleep 0.1
    hangon keys "$session" "enter"; sleep 0.3
}
set_tab_width "${QA_SESSION}_a" 4
sleep 0.2

col_b_before=$(marker_col "${QA_SESSION}_b" "MARKERTAB_B")

# Change tab width in session A only.
set_tab_width "${QA_SESSION}_a" 9

# Session B has not been told to re-check yet -- nudge it with a keystroke
# (triggers render() -> the debounced check_for_changes()) and poll for
# the marker to shift, respecting the ~1s debounce window rather than
# asserting instant propagation (which the fix deliberately removes).
t0=$(qa_perf_now)
poll_deadline=$(perl -e "printf '%.3f', $t0 + 6")
col_b_after="$col_b_before"
while :; do
    hangon keys "${QA_SESSION}_b" "right" >/dev/null; sleep 0.3
    col_b_after=$(marker_col "${QA_SESSION}_b" "MARKERTAB_B")
    if [[ "$col_b_after" != "$col_b_before" ]]; then
        break
    fi
    now=$(qa_perf_now)
    if perl -e "exit(($now >= $poll_deadline) ? 0 : 1)"; then
        break
    fi
done
elapsed=$(perl -e "printf '%.2f', $(qa_perf_now) - $t0")

if [[ -n "$col_b_before" && -n "$col_b_after" && "$col_b_after" != "$col_b_before" ]]; then
    qa_pass "session B picked up session A's tab-width change within ${elapsed}s (col $col_b_before -> $col_b_after) -- cross-instance sync still works, debounced not broken"
else
    qa_fail "session B picks up session A's tab-width preference change" \
        "col_before=$col_b_before col_after=$col_b_after after ${elapsed}s -- check_for_changes() may be over-debounced or broken, not just less eager"
fi

hangon stop "${QA_SESSION}_a" 2>/dev/null || true
hangon stop "${QA_SESSION}_b" 2>/dev/null || true
qa_summary
