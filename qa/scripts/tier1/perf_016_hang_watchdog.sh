#!/usr/bin/env bash
# QA-PERF-016: Hang watchdog detects a wedged main loop and recovers
#
# Feature (bugs.md Phase 2): Editor::run forks a watchdog process
# (lib/Zepto/HangWatchdog.pm) connected via a pipe. The main loop sends
# heartbeats; if none arrive within the threshold, the watchdog writes a
# diagnostic log and signals the parent, which appends a stack trace and
# recovers with a status-bar notice.
#
# This test can't rely on Phase 6a's transform timeout to create a hang
# (that timeout would just recover the transform on its own) — instead it
# sets ZEPTO_HANG_THRESHOLD low and ZEPTO_TRANSFORM_TIMEOUT higher, so a
# `sleep` transform genuinely blocks the main loop past the watchdog
# threshold while still completing on its own well before the transform
# timeout would intervene.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PERF-016: Hang watchdog detects and recovers from a wedged loop"

export ZEPTO_HANG_THRESHOLD=2
export ZEPTO_TRANSFORM_TIMEOUT=20

file=$(qa_tmpfile_nl "perf016.txt" "watchdog test content")
qa_start "$file"

qa_keys "ctrl-a"
qa_keys "alt-t"
qa_assert_screen "Shell" "transform input visible"
qa_keys "ctrl-a" 0.1
qa_send "sleep 8" 0.2
qa_keys "enter"

# Poll for the diagnostic log to appear — must show up well before the
# 8s sleep finishes, proving the watchdog (a separate process) detected
# the wedge independently, not just "eventually noticed after the fact".
log_deadline=$(($(date +%s) + 6))
log_path=""
while [[ $(date +%s) -lt $log_deadline ]]; do
    candidate=$(ls "$QA_STATE_DIR"/hang-*.log 2>/dev/null | head -1) || true
    if [[ -n "$candidate" ]]; then
        log_path="$candidate"
        break
    fi
    sleep 0.2
done

if [[ -n "$log_path" ]]; then
    qa_pass "diagnostic log appeared before the transform finished (watchdog detected the wedge independently)"
else
    qa_fail "no diagnostic log appeared within budget" "checked $QA_STATE_DIR"
fi

if [[ -n "$log_path" ]] && grep -q "transform:sleep 8" "$log_path"; then
    qa_pass "log records the last heartbeat tag (transform:sleep 8)"
else
    qa_fail "log missing expected heartbeat tag" "$(cat "$log_path" 2>/dev/null | head -5)"
fi

# Wait for the transform to actually finish and the editor to recover.
qa_expect_screen "unresponsive" 15 -F || true
qa_assert_screen "unresponsive" "status bar shows the recovery notice"

# The SAME log file should now also have the parent-side stack trace
# appended (written by the SIGUSR2 handler on recovery).
if [[ -n "$log_path" ]] && grep -q "Parent-side diagnostics" "$log_path"; then
    qa_pass "parent-side stack trace was appended to the same log file"
else
    qa_fail "parent-side diagnostics not found in log" "$(cat "$log_path" 2>/dev/null)"
fi

# Confirm full responsiveness, not just unfrozen-but-wedged.
qa_send "RESPONSIVE456"
sleep 0.3
qa_assert_screen "RESPONSIVE456" "editor fully responsive after recovery"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
