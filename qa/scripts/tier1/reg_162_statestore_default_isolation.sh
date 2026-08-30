#!/usr/bin/env bash
# QA-REG-162: Zepto::Editor's default StateStore no longer defaults to the
# developer's real ~/.config/zepto when running under the test harness, and
# CLAUDE.md's Testing Workflow example no longer teaches an unsafe pattern.
#
# Bug: Editor.pm:87 did `state_store => $opts{state_store} // Zepto::StateStore->new()`,
# which falls back to the real $XDG_CONFIG_HOME/zepto (or ~/.config/zepto)
# when no state_store is given. Over 100 `Zepto::Editor->new(...)` calls in
# tests/editor.t (plus tests/find.t, tests/multi_cursor.t, tests/renderer.t)
# relied on this implicitly, so unit tests silently read/wrote the real
# machine's preferences. Separately, CLAUDE.md's own Testing Workflow
# example (`hangon start process --name zepto -- ./zepto /tmp/testfile.txt`)
# showed no --state-dir, so following the docs literally for interactive
# testing did the same thing. One incident actually flipped
# auto_pairs/mouse_enabled/restore_session/soft_tabs on the dev machine.
#
# Fix: Editor.pm now redirects its default-StateStore fallback to a fresh
# File::Temp::tempdir() per call when $ENV{HARNESS_ACTIVE} is set (i.e.
# under `prove`), leaving real end-user/non-harness behavior unchanged.
# CLAUDE.md's example now shows --state-dir explicitly. See bugs.md P1
# "Zepto::Editor->new() defaults to the developer's real ~/.config/zepto
# StateStore" and tests/editor.t's "Editor->new() with no state_store never
# touches the real config dir under the test harness" for the unit-level
# coverage of the Editor.pm fix itself — this script covers the two things
# a Perl unit test can't: the doc text, and a real end-to-end run of the
# compiled binary with an explicit --state-dir.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-162: StateStore default isolation (docs + real --state-dir run)"

# ---------------------------------------------------------------------------
# 1. CLAUDE.md's Testing Workflow example must show --state-dir, not a bare
#    `./zepto FILE` invocation, so anyone following it literally is safe.
# ---------------------------------------------------------------------------
claude_md="$(dirname "$0")/../../../CLAUDE.md"
if [[ -f "$claude_md" ]]; then
    example_line=$(grep -m1 'hangon start process --name zepto -- \./zepto' "$claude_md" || true)
    if [[ -n "$example_line" ]] && echo "$example_line" | grep -q -- '--state-dir'; then
        qa_pass "CLAUDE.md's Testing Workflow example uses --state-dir"
    else
        qa_fail "CLAUDE.md's Testing Workflow example uses --state-dir" \
            "example line: ${example_line:-<not found>}"
    fi
else
    qa_fail "CLAUDE.md's Testing Workflow example uses --state-dir" "CLAUDE.md not found at $claude_md"
fi

# ---------------------------------------------------------------------------
# 2. Running the real binary with an explicit --state-dir must never touch
#    the real ~/.config/zepto (or $XDG_CONFIG_HOME/zepto), even while
#    actively toggling a preference — the exact action that corrupted the
#    dev machine's real prefs in the original incident.
# ---------------------------------------------------------------------------
real_xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
real_prefs="$real_xdg/zepto/preferences.json"
mtime_before=""
if [[ -f "$real_prefs" ]]; then
    mtime_before=$(stat -f '%m' "$real_prefs" 2>/dev/null || stat -c '%Y' "$real_prefs" 2>/dev/null || true)
fi

scratch_state="$QA_TMPDIR/reg162_explicit_state"
mkdir -p "$scratch_state"
file=$(qa_tmpfile_nl "reg162.txt" "hello")

hangon start process --name "${QA_SESSION}_162" -- "$QA_ZEPTO" \
    --state-dir "$scratch_state" --no-system-clipboard "$file"
sleep "$QA_RENDER_WAIT"

# Toggle a preference through the real UI (Soft Tabs), same as the original
# incident's repro, then quit.
hangon keys "${QA_SESSION}_162" "ctrl-space"; sleep 0.3
hangon send "${QA_SESSION}_162" "soft tabs"; sleep 0.3
hangon keys "${QA_SESSION}_162" "enter"; sleep 0.3
hangon keys "${QA_SESSION}_162" "ctrl-q"; sleep 0.3
hangon stop "${QA_SESSION}_162" 2>/dev/null || true

if [[ -f "$scratch_state/preferences.json" ]]; then
    qa_pass "preference write landed in the explicit --state-dir, not the real config dir"
else
    qa_fail "preference write landed in the explicit --state-dir, not the real config dir" \
        "no preferences.json under $scratch_state"
fi

mtime_after=""
if [[ -f "$real_prefs" ]]; then
    mtime_after=$(stat -f '%m' "$real_prefs" 2>/dev/null || stat -c '%Y' "$real_prefs" 2>/dev/null || true)
fi

if [[ "$mtime_before" == "$mtime_after" ]]; then
    qa_pass "real $real_prefs was not created or modified by this run"
else
    qa_fail "real $real_prefs was not created or modified by this run" \
        "mtime changed: before='$mtime_before' after='$mtime_after'"
fi

qa_summary
