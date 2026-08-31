#!/usr/bin/env bash
# QA-FIND-010: Replace single occurrence
#
# Enter in the replace field defaults to Replace-ALL mode
# (Editor.pm's `find_replace_all => 1` default) -- reaching single-replace
# mode requires Shift+Tab, which is NOT in hangon's named `keys` list (see
# reg_009_shift_tab_fif.sh's note). It IS reachable via raw CSI injection
# though: InputParser.pm maps the raw byte sequence ESC [ Z (`\x1b[Z`,
# standard VT220 "back-tab") to a Shift+Tab key event, the same technique
# reg_202_csiu_special_keys.sh already established for other
# hangon-key-list gaps. Confirmed interactively before writing this: one
# Shift+Tab from the default replace-all state toggles
# `find_replace_all` off without touching regex/case.
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

# Switch from the default Replace-All to Replace-One mode (Shift+Tab)
printf '\x1b[Z' | qa_raw_stdin

# Replace single (Enter in single-replace mode replaces only the current match)
qa_keys "enter" 0.3

# Save and check
qa_keys "escape"
qa_keys "ctrl-s"
sleep 0.3

# File should have exactly one "aaa" replaced with "ZZZ", 2 remaining.
# `|| true` guards each grep -o against its own "no match" exit 1, which
# would otherwise abort the script under qa-helpers.sh's `set -e
# -o pipefail` before any PASS/FAIL is ever printed (this exact silent
# crash is what QA-REG-203's investigation found happening here after the
# preview/pre-select fix stopped an unrelated bug from accidentally
# leaving both substrings present).
content=$(cat "$file")
zzz_count=$(echo "$content" | { grep -o "ZZZ" || true; } | wc -l | tr -d ' ')
aaa_count=$(echo "$content" | { grep -o "aaa" || true; } | wc -l | tr -d ' ')

if [[ "$zzz_count" -eq 1 && "$aaa_count" -eq 2 ]]; then
    qa_pass "single replace: exactly 1 ZZZ, 2 aaa remaining"
else
    qa_fail "single replace (expected ZZZ=1, aaa=2)" "got ZZZ=$zzz_count, aaa=$aaa_count"
fi

qa_keys "ctrl-q"
qa_summary
