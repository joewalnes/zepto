#!/usr/bin/env bash
# QA-PERF-019: Rapid sequential typing on a large file keeps up within
# budget (not a hang, not gross sluggishness)
#
# See qa/lib/qa-perf-helpers.sh header for why this is timing-based, not
# vision-based, and for the pass/slow/hang distinction.
#
# "Rapid sequential typing" is simulated as a burst of individually-sent
# characters (each its own `hangon send` call, no delay between them) —
# deliberately more adversarial than a single batched string send, since
# it forces the editor to actually keep up with per-keystroke event
# handling rather than possibly optimizing for one big paste-like write.
# The budget below intentionally includes real hangon/tmux CLI overhead
# per character (unavoidable with this harness) on top of editor time,
# which is part of why the threshold is generous.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-PERF-019: Rapid sequential typing on a large file"

content=""
for i in $(seq 1 20000); do content+="perftypeline${i}"$'\n'; done
file=$(qa_tmpfile_nl "perf019.txt" "$content")
qa_start "$file"

# Jump to a line deep in the file (not the top, where a naive
# implementation might stay artificially fast) and type at its front.
qa_keys "ctrl-g" 0.1
qa_send "10000" 0.2
qa_keys "enter" 0.3

burst="RAPIDTYPETEST1234567890"
t0=$(qa_perf_now)
for (( i=0; i<${#burst}; i++ )); do
    qa_send "${burst:$i:1}" 0
done

qa_assert_perf "30-char rapid burst lands and renders on a 20K-line file" 8 "RAPIDTYPETEST1234567890perftypeline10000" 25 "$t0"

qa_keys "ctrl-q" 0.2
sleep 0.2
qa_send "n" 0.2   # decline save if a dirty-quit prompt appears
qa_summary
