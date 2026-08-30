#!/usr/bin/env bash
# QA-PERF-016: Opening a large file renders within a generous time budget
# (not a hang, not gross sluggishness)
#
# Part of the perf/hang-detection sweep (qa/lib/qa-perf-helpers.sh) — see
# that file's header for why this class of check is NOT vision-based: a
# screenshot can't tell you an operation took 3 seconds, only real wall-
# clock timing can. Threshold is deliberately generous (a real regression
# should blow well past it, not brush against it) — see qa-perf-helpers.sh
# header for the "why generous" rationale.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-PERF-016: Large file opens within budget"

# ~50K lines / ~1MB, matching the size class QA-PERF-003's guideline
# ("a few seconds") already targets.
content=""
for i in $(seq 1 50000); do content+="perfline${i}_marker_content_here"$'\n'; done
file=$(qa_tmpfile_nl "perf016.txt" "$content")

# Bypass qa_start's built-in QA_RENDER_WAIT sleep so the timer starts as
# close as possible to the real "process launched" moment — same
# underlying `hangon start process` call qa_start makes.
t0=$(qa_perf_now)
hangon start process --name "$QA_SESSION" -- "$QA_ZEPTO" \
    --state-dir "$QA_STATE_DIR" --no-system-clipboard "$file"

qa_assert_perf "50K-line file opens and first line renders" 5 "perfline1_marker_content_here" 20 "$t0"

qa_keys "ctrl-q" 0.2
qa_summary
