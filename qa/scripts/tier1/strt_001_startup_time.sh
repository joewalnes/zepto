#!/usr/bin/env bash
# QA-STRT-001: Editor starts within reasonable time
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-STRT-001: Startup time"

file=$(qa_tmpfile_nl "strt001.txt" "hello")

start_time=$(date +%s)
qa_start "$file"
end_time=$(date +%s)

elapsed=$((end_time - start_time))
# Should start within 3 seconds (qa_start includes render wait)
if [[ $elapsed -le 3 ]]; then
    qa_pass "started in ${elapsed}s"
else
    qa_fail "started in ${elapsed}s (expected <= 3s)"
fi

qa_assert_screen "hello" "content visible after startup"

qa_keys "ctrl-q"
qa_summary
