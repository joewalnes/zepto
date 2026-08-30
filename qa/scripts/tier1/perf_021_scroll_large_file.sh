#!/usr/bin/env bash
# QA-PERF-021: Rapid scrolling through a large file keeps up within
# budget (not a hang, not gross sluggishness)
#
# See qa/lib/qa-perf-helpers.sh header for why this is timing-based, not
# vision-based, and for the pass/slow/hang distinction.
#
# Unlike the other perf_* scripts, this one does NOT use
# qa_assert_perf/qa_perf_poll_for's pattern-match polling — the exact
# line PageDown lands on per press depends on terminal height and isn't
# worth hardcoding (see git history of this file for the earlier,
# fragile attempt at predicting it exactly). Instead it polls the
# NUMERIC cursor line via qa_cursor_pos (qa-helpers.sh) until it clears a
# threshold that's only reachable by real forward scroll progress — a
# broken/hung PageDown that leaves the cursor at/near line 1 will
# correctly time out and FAIL, so this isn't a "screen changed" style
# tautological check (see qa/README.md's anti-pattern list).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-PERF-021: Rapid scroll through a large file"

content=""
for i in $(seq 1 3000); do content+="scrollline${i} of the perf test file"$'\n'; done
file=$(qa_tmpfile_nl "perf021.txt" "$content")
qa_start "$file"

qa_cursor_pos
if [[ "$QA_CURSOR_LINE" != "1" ]]; then
    qa_fail "sanity: starts at line 1" "got line $QA_CURSOR_LINE"
fi

THRESHOLD=200
BUDGET=4
POLL_TIMEOUT=20

t0=$(qa_perf_now)
# Rapid burst -- 12 PageDowns with no settle delay between them. Even a
# conservative ~20 lines/page clears the threshold several times over;
# the point is sustained responsiveness under a rapid burst, not landing
# on an exact line.
for _ in $(seq 1 12); do qa_keys "pagedown" 0; done

found=0
while :; do
    qa_cursor_pos
    if [[ -n "$QA_CURSOR_LINE" && "$QA_CURSOR_LINE" -ge "$THRESHOLD" ]]; then
        found=1
        break
    fi
    now=$(qa_perf_now)
    elapsed=$(perl -e "printf '%.3f', $now - $t0")
    if perl -e "exit(($elapsed >= $POLL_TIMEOUT) ? 0 : 1)"; then
        QA_PERF_ELAPSED="$elapsed"
        break
    fi
    sleep 0.1
done
now=$(qa_perf_now)
QA_PERF_ELAPSED=$(perl -e "printf '%.3f', $now - $t0")

if [[ "$found" == "1" ]]; then
    if perl -e "exit(($QA_PERF_ELAPSED <= $BUDGET) ? 0 : 1)"; then
        qa_pass "rapid 12-PageDown burst cleared line ${THRESHOLD}+ (${QA_PERF_ELAPSED}s, budget ${BUDGET}s)"
    else
        qa_fail "rapid 12-PageDown burst cleared line ${THRESHOLD}+" \
            "SLOW: took ${QA_PERF_ELAPSED}s, exceeds ${BUDGET}s budget (cursor did move — this is slowness, not a hang)"
    fi
else
    qa_fail "rapid 12-PageDown burst cleared line ${THRESHOLD}+" \
        "HANG/BROKEN: cursor never reached line ${THRESHOLD} within ${POLL_TIMEOUT}s (still at line ${QA_CURSOR_LINE:-unknown}) -- process may be hung, or PageDown silently failed"
fi

qa_keys "ctrl-q" 0.2
qa_summary
