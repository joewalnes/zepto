#!/usr/bin/env bash
# QA-FILE-005: Atomic save uses temp file
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FILE-005: Atomic save"

file=$(qa_tmpfile_nl "file005.txt" "original content")
qa_start "$file"

qa_send " modified"
qa_keys "ctrl-s"
sleep 0.5

# Verify saved content
qa_assert_file_contains "$file" "modified" "file saved with modifications"

# Verify no temp files left behind
leftover=$(ls "$QA_TMPDIR"/.file005* 2>/dev/null | wc -l || true)
if [[ "$leftover" -eq 0 ]]; then
    qa_pass "no temp files left behind"
else
    qa_fail "temp files left behind: $leftover"
fi

qa_keys "ctrl-q"
qa_summary
