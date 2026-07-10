#!/usr/bin/env bash
# QA-XFM-014: Hung transform command times out instead of freezing the editor
#
# bugs.md P1 "cmd_transform open3 sequential-slurp can deadlock/hang UI
# indefinitely": Editor::_run_shell_pump replaced sequential blocking
# IPC::Open3 reads/writes with a select()-driven pump plus a hard
# wall-clock timeout. Uses ZEPTO_TRANSFORM_TIMEOUT (env-overridable, see
# Editor/Commands.pm cmd_transform) to keep this test fast — qa_start
# forwards all ZEPTO_* vars through the command line (see qa-helpers.sh
# qa_start isolation note).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-014: Hung transform times out, editor recovers"

export ZEPTO_TRANSFORM_TIMEOUT=2

file=$(qa_tmpfile_nl "xfm014.txt" "do not touch me")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
qa_assert_screen "Shell" "transform input visible"

# Clear any pre-filled command from a previous run's history, then type a
# command that hangs forever.
qa_keys "ctrl-a" 0.1
qa_send "sleep 30" 0.2
qa_keys "enter"

# Poll for recovery instead of a fixed sleep — should land well before the
# full 30s sleep would, bounded generously at 8s (2s timeout + slack).
start_ts=$(date +%s)
recovered=0
for _ in $(seq 1 40); do
    qa_screen
    if echo "$QA_SCREEN" | grep -qi "timed out"; then
        recovered=1
        break
    fi
    sleep 0.2
done
end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))

if [[ "$recovered" == "1" ]]; then
    qa_pass "editor recovered with a timeout message (${elapsed}s, not 30s)"
else
    qa_fail "editor did not recover / show a timeout message" "$(echo "$QA_SCREEN" | tail -3)"
fi

if [[ "$elapsed" -lt 12 ]]; then
    qa_pass "recovery happened well within budget (${elapsed}s < 12s)"
else
    qa_fail "recovery took too long" "${elapsed}s"
fi

qa_assert_screen "do not touch me" "buffer content unchanged after timeout"

# Confirm the editor is actually responsive, not just unfrozen-but-wedged.
# The Ctrl+A selection from before the transform is still active (the
# timeout path leaves it untouched, same as a normal failed/cancelled
# transform) — typing now replaces the selection, which is itself proof
# the keystroke was processed normally.
qa_send "RESPONSIVE123"
sleep 0.3
qa_assert_screen "RESPONSIVE123" "typed text landed — editor fully responsive"
qa_assert_not_screen "do not touch me" "selection was replaced by the typed text (normal editor behavior)"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
