#!/usr/bin/env bash
# QA-SEC-006: Atomic save uses File::Temp with unpredictable names
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-006: Atomic save with File::Temp"

file=$(qa_tmpfile_nl "sec006.txt" "original content")
qa_start "$file"

# Modify and save
qa_keys "end"
qa_send " modified"
qa_keys "ctrl-s"
sleep 0.5

# Verify file was saved correctly
qa_assert_file_contains "$file" "original content modified" "file saved correctly"

# Check no predictable temp files left behind
leftover=$(ls "$QA_TMPDIR"/*.zepto.tmp.* 2>/dev/null | wc -l | tr -d ' ' || true)
if [[ "$leftover" -eq 0 ]]; then
    qa_pass "no predictable temp files left behind"
else
    qa_fail "no predictable temp files left behind" "found $leftover"
fi

qa_keys "ctrl-q"
qa_summary
