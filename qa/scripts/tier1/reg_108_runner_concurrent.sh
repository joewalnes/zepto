#!/usr/bin/env bash
# QA-REG-108: QA runner never kills live foreign hangon sessions
# Bug: runner.pl ran `hangon stopall` and deleted ~/.hangon/state.json,
# killing every session on the machine — fatal when multiple agents or
# runners share the hangon server. It now stops only stale zqa_* sessions
# (owning script PID dead).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-108: Runner concurrency safety"

# A live "foreign" session (another agent's interactive session)
foreign="reg108_foreign_$$"
hangon start process --name "$foreign" -- sleep 60 >/dev/null 2>&1

# A live zqa_* session whose owning PID is alive (simulates a concurrent
# QA script mid-run)
sleep 60 &
livepid=$!
hangon start process --name "zqa_${livepid}" -- sleep 60 >/dev/null 2>&1

# A stale zqa_* session (owning PID long dead)
hangon start process --name "zqa_99999999" -- sleep 60 >/dev/null 2>&1

# Run the runner on a single trivial script
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
( cd "$repo_root" && perl qa/runner.pl --tier 1 --filter cli_005 >/dev/null 2>&1 ) || true

listing=$(hangon list 2>/dev/null || echo "")
if echo "$listing" | grep -q "$foreign"; then
    qa_pass "live foreign session survived a runner invocation"
else
    qa_fail "live foreign session survived a runner invocation"
fi
if echo "$listing" | grep -q "zqa_${livepid}"; then
    qa_pass "live zqa session (owner alive) survived"
else
    qa_fail "live zqa session (owner alive) survived"
fi
if echo "$listing" | grep -q "zqa_99999999"; then
    qa_fail "stale zqa session was cleaned up" "still present"
else
    qa_pass "stale zqa session was cleaned up"
fi

hangon stop "$foreign" >/dev/null 2>&1 || true
hangon stop "zqa_${livepid}" >/dev/null 2>&1 || true
kill "$livepid" 2>/dev/null || true
qa_summary
