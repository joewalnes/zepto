#!/usr/bin/env bash
# QA-PERF-018: Replace All across many matches completes within budget
# (not a hang, not gross sluggishness)
#
# See qa/lib/qa-perf-helpers.sh header for why this is timing-based, not
# vision-based, and for the pass/slow/hang distinction.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-PERF-018: Replace All across many matches completes within budget"

# 3000 lines, each with exactly one "foo" match -- 3000 total matches.
content=""
for i in $(seq 1 3000); do content+="abc foo xyz${i}"$'\n'; done
file=$(qa_tmpfile_nl "perf018.txt" "$content")
qa_start "$file"

# Open find/replace, fill both fields (same recipe as
# find_006_replace_all.sh, the established Replace-All trigger sequence).
qa_keys "ctrl-f" 0.1
qa_send "foo" 0.3
qa_keys "tab" 0.2
qa_keys "ctrl-a" 0.1
qa_send "ZZZ" 0.3

t0=$(qa_perf_now)
qa_keys "enter" 0   # commits Replace All

# Cursor stays at line 1 (top of file, already the viewport), so line 1
# turning from "abc foo xyz1" to "abc ZZZ xyz1" is an exact, unambiguous
# signal that all 3000 replacements finished and re-rendered.
qa_assert_perf "3000-match Replace All completes and renders" 4 "abc ZZZ xyz1" 20 "$t0"

qa_keys "escape" 0.2
qa_keys "ctrl-q" 0.2
sleep 0.2
qa_send "n" 0.2   # decline save if a dirty-quit prompt appears
qa_summary
