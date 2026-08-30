#!/usr/bin/env bash
# ===========================================================================
# qa-perf-helpers.sh — timing/hang-detection utilities for Zepto QA scripts
# ===========================================================================
# A vision LLM judge looking at one screenshot cannot tell you an operation
# took 3 seconds — that needs real timing instrumentation, not pixel
# analysis. These helpers measure real wall-clock time between "input was
# sent" and "the expected result appeared on screen", by polling `hangon
# screen` at a short interval. Deliberately NOT LLM-based — pure tier1,
# fast, free, no API key needed.
#
# Source this AFTER qa-helpers.sh (it depends on qa_screen/QA_SESSION):
#   source "$(dirname "$0")/../../lib/qa-helpers.sh"
#   source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
#
# Core idea — distinguish three outcomes, not just pass/fail:
#   FAST enough  — pattern appeared within the budget.         -> PASS
#   SLOW         — pattern appeared, but later than the budget -> FAIL (slow)
#   HUNG/BROKEN  — pattern never appeared at all                -> FAIL (hang)
# The failure message always says which of the two FAIL cases it was —
# "slow" and "hung" need different follow-up, and collapsing them into one
# generic failure would make triage harder.
#
# Thresholds in scripts that use this file are deliberately generous
# (multi-second budgets on multi-thousand-line fixtures). The goal is
# catching gross regressions and hangs, not micro-benchmarking — a
# threshold tight enough to flake on a loaded CI box is worse than useless.
# ===========================================================================

# Wall-clock time in seconds with millisecond precision, portable across
# macOS (BSD date has no %N) and Linux. Uses Perl (already a hard
# dependency of this whole test suite) rather than `date +%s.%N`, which
# silently prints a literal "N" on macOS instead of nanoseconds.
qa_perf_now() {
    perl -MTime::HiRes=time -e 'printf "%.3f", time'
}

# Poll `hangon screen` for PATTERN until it appears or TIMEOUT seconds
# elapse, starting the clock at T0 (a qa_perf_now timestamp) if given,
# else at the moment this function is called.
#
#   qa_perf_poll_for PATTERN TIMEOUT [T0]
#
# Sets QA_PERF_ELAPSED (seconds, 3dp) and QA_PERF_FOUND (1/0) either way.
# Returns 0 if PATTERN appeared, 1 on timeout (mirrors qa_wait_screen).
#
# IMPORTANT: pass T0 explicitly whenever the timed action itself takes
# non-trivial time to send (e.g. a qa_send/qa_keys call, which sleeps
# QA_RENDER_WAIT afterward by default) — capture qa_perf_now BEFORE that
# call so the send time counts toward the measurement, matching what a
# real user would experience. Call action helpers with an explicit "0"
# delay arg (e.g. `qa_keys "ctrl-s" 0`) to skip their built-in settle
# sleep so it doesn't pad every measurement by QA_RENDER_WAIT.
qa_perf_poll_for() {
    local pattern="$1"
    local timeout="${2:-10}"
    local t0="${3:-$(qa_perf_now)}"
    local interval=0.1
    local now elapsed
    while :; do
        qa_screen
        if echo "$QA_SCREEN" | grep -qE "$pattern"; then
            now=$(qa_perf_now)
            QA_PERF_ELAPSED=$(perl -e "printf '%.3f', $now - $t0")
            QA_PERF_FOUND=1
            return 0
        fi
        now=$(qa_perf_now)
        elapsed=$(perl -e "printf '%.3f', $now - $t0")
        if perl -e "exit(($elapsed >= $timeout) ? 0 : 1)"; then
            QA_PERF_ELAPSED="$elapsed"
            QA_PERF_FOUND=0
            return 1
        fi
        sleep "$interval"
    done
}

# Assert that PATTERN appeared on screen within MAX_SECONDS of T0 (or of
# this call, if T0 omitted). Polls up to POLL_TIMEOUT seconds total (must
# be >= MAX_SECONDS; defaults to 4x budget + 5s of slack) so a genuinely
# slow-but-not-hung operation is reported as "slow", not lumped in with a
# true hang.
#
#   t0=$(qa_perf_now)
#   qa_keys "ctrl-s" 0                       # send with no settle sleep
#   qa_assert_perf "save completes" 2 "saved" 15 "$t0"
#
#   qa_assert_perf DESC MAX_SECONDS PATTERN [POLL_TIMEOUT] [T0]
qa_assert_perf() {
    local desc="$1" max_seconds="$2" pattern="$3"
    local poll_timeout="${4:-}"
    local t0="${5:-$(qa_perf_now)}"
    if [[ -z "$poll_timeout" ]]; then
        poll_timeout=$(perl -e "printf '%d', $max_seconds * 4 + 5")
    fi
    if qa_perf_poll_for "$pattern" "$poll_timeout" "$t0"; then
        if perl -e "exit(($QA_PERF_ELAPSED <= $max_seconds) ? 0 : 1)"; then
            qa_pass "$desc (${QA_PERF_ELAPSED}s, budget ${max_seconds}s)"
        else
            qa_fail "$desc" "SLOW: took ${QA_PERF_ELAPSED}s, exceeds ${max_seconds}s budget (pattern did eventually appear — this is slowness, not a hang)"
        fi
    else
        qa_fail "$desc" "HANG/BROKEN: pattern '$pattern' never appeared within ${poll_timeout}s (budget was ${max_seconds}s) — process may be hung, or the operation silently failed"
    fi
}
