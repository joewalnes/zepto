#!/usr/bin/env bash
# QA-FIND-010: Replace single occurrence
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-010: Replace single"

file=$(qa_tmpfile_nl "find010.txt" "aaa bbb aaa
ccc aaa ddd")
qa_start "$file"

# Open find
qa_keys "ctrl-f"
qa_send "aaa" 0.3

# Tab to replace field
qa_keys "tab"
qa_send "ZZZ" 0.3

# Replace single (Enter in replace field replaces current match)
qa_keys "enter" 0.3

# Save and check
qa_keys "escape"
qa_keys "ctrl-s"
sleep 0.3

# File should have one aaa replaced with ZZZ but others remain
content=$(cat "$file")
zzz_count=$(echo "$content" | grep -o "ZZZ" | wc -l | tr -d ' ')
aaa_count=$(echo "$content" | grep -o "aaa" | wc -l | tr -d ' ')

if [[ "$zzz_count" -ge 1 && "$aaa_count" -ge 1 ]]; then
    qa_pass "single replace: $zzz_count ZZZ, $aaa_count aaa remaining"
else
    qa_fail "single replace (ZZZ=$zzz_count, aaa=$aaa_count)"
fi

qa_keys "ctrl-q"
qa_summary
