#!/usr/bin/env bash
# QA-SEC-012 / QA-REG-141: ReDoS protection covers regex MATCH time, not
# just compilation.
#
# Bug: FindEngine.pm's SIGALRM(1) timeout wrapped only qr// compilation
# (_build_regex) and was explicitly cancelled before the caller ever
# attempted a match. Catastrophic backtracking happens at MATCH time, so
# that alarm provided zero protection against it -- a pathological
# pattern could hang tick()/_search_range() (and thus the whole editor)
# indefinitely, even though QA-SEC-005 had already "verified" ReDoS
# protection existed.
#
# QA-SEC-005 used the textbook `(a+)+$` demo pattern, which does NOT
# actually reproduce this bug: Perl's own regex engine auto-optimizes
# away nested quantifiers over identical single-char atoms, so that
# pattern matches/fails near-instantly in Perl regardless of the
# match-time alarm. This test uses `(a?){28}a{28}` instead -- a
# counted-repetition-of-optional form that genuinely causes catastrophic
# backtracking in Perl (verified separately to take 15+ seconds of pure
# backtracking on unguarded code) while still compiling instantly, so it
# specifically exercises the gap QA-SEC-005 didn't.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-012: ReDoS match-time timeout protection"

# 28 "a" characters, nothing else -- no trailing character that would
# let a naive engine bail out early.
content=$(printf 'a%.0s' $(seq 1 28))
file=$(qa_tmpfile_nl "sec012.txt" "$content")
qa_start "$file"

# Open find with regex mode
qa_keys "ctrl-f"
qa_keys "ctrl-r" 0.2

# Type the catastrophic-backtracking pattern
qa_send '(a?){28}a{28}' 0.2

# With the fix, a single match attempt is capped at ~1s (MATCH_ALARM_SECS
# in FindEngine.pm). Poll for the find bar to settle on a result
# (matches or "No matches") instead of a fixed sleep -- this both proves
# the editor is still rendering (not hung) and bounds the wait.
if qa_wait_screen 'No matches|[0-9]+ of [0-9]+' 6; then
    qa_pass "search settled (did not hang) within 6s of typing the pattern"
else
    qa_fail "search settled (did not hang) within 6s of typing the pattern" \
        "find bar never showed a match count or 'No matches'"
fi

# Editor must still be alive and responsive -- not just the render
# thread stalled mid-crash.
if qa_alive; then
    qa_pass "editor process still alive after catastrophic regex"
else
    qa_fail "editor process still alive after catastrophic regex" "process died"
fi

# Prove actual responsiveness, not just an alive-but-wedged process:
# escape out of find, type a character, confirm it lands.
qa_keys "escape" 0.2
qa_keys "end" 0.2
qa_send "ZQA_MARKER" 0.2
qa_assert_expect "ZQA_MARKER" "editor accepts and renders new input after the timeout"

# Undo the marker edit so we leave a clean buffer, then quit without saving.
qa_keys "ctrl-z" 0.2

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
