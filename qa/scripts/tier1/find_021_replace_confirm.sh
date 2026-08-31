#!/usr/bin/env bash
# QA-FIND-021: Replace single confirms before replacing
#
# See find_010_replace_single.sh's header comment for why this needs a
# raw Shift+Tab (`\x1b[Z`) to reach single-replace mode -- Enter defaults
# to Replace-ALL, and Shift+Tab isn't in hangon's named `keys` list.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-021: Replace single confirmation"

file=$(qa_tmpfile_nl "find021.txt" "aaa bbb aaa
ccc aaa ddd")
qa_start "$file"

qa_keys "ctrl-f"
qa_send "aaa" 0.3

# Tab to replace field
qa_keys "tab"
qa_send "ZZZ" 0.3

# Switch from the default Replace-All to Replace-One mode (Shift+Tab)
printf '\x1b[Z' | qa_raw_stdin

# Replace single
qa_keys "enter" 0.3

# Save and verify only one replaced
qa_keys "escape"
qa_keys "ctrl-s"
sleep 0.3

# `|| true` guards each grep -o against its own "no match" exit 1 under
# qa-helpers.sh's `set -e -o pipefail` -- see find_010_replace_single.sh's
# header comment for the full explanation.
content=$(cat "$file")
zzz_count=$(echo "$content" | { grep -o "ZZZ" || true; } | wc -l | tr -d ' ')
aaa_count=$(echo "$content" | { grep -o "aaa" || true; } | wc -l | tr -d ' ')

if [[ "$zzz_count" -eq 1 && "$aaa_count" -eq 2 ]]; then
    qa_pass "single replace: exactly 1 replaced, 2 remaining"
else
    qa_fail "single replace (expected ZZZ=1, aaa=2)" "got ZZZ=$zzz_count, aaa=$aaa_count"
fi

qa_keys "ctrl-q"
qa_summary
