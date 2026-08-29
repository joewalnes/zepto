#!/usr/bin/env bash
# QA-LINE-010: Alt+U duplicates current line down (direct shortcut)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-LINE-010: Duplicate line down via Alt+U shortcut"

file=$(qa_tmpfile_nl "line010.txt" "alpha
beta
gamma")
qa_start "$file"

# Cursor starts on line 1 ("alpha"). Alt+U should insert a duplicate
# directly below and move the cursor onto the new (lower) copy — the
# same behavior as the palette-only "Duplicate Down" command, but
# reachable without opening the palette.
qa_keys "alt-u"

qa_screen
count=$(echo "$QA_SCREEN" | grep -c "alpha" || true)
if [[ "$count" -ge 2 ]]; then
    qa_pass "Alt+U duplicated the line (found $count copies)"
else
    qa_fail "Alt+U duplicated the line" "expected >=2 'alpha' occurrences, found $count"
fi

# Verify ordering: alpha, alpha, beta, gamma — proves the duplicate
# landed BELOW the original, not above (which would be indistinguishable
# from Ctrl+U / Duplicate Up if we only grepped for a count). Gutter
# padding differs on the cursor row, so compare the word sequence only,
# not raw substrings with assumed spacing.
qa_screen
seq=$(echo "$QA_SCREEN" | grep -oE '(alpha|beta|gamma)' | tr '\n' ',' )
if [[ "$seq" == "alpha,alpha,beta,gamma," ]]; then
    qa_pass "duplicate inserted below original (line order: alpha, alpha, beta, gamma)"
else
    qa_fail "duplicate inserted below original" "got order: $seq"
fi

# Cursor should follow to the new lower duplicate (line 2), not stay
# on line 1 — this is what distinguishes "Down" from "Up".
qa_assert_cursor_at 2 "cursor moved to the new (lower) duplicate line"

# Undo should restore to exactly 3 lines with no leftover duplicate.
qa_keys "ctrl-z"
qa_screen
count_after_undo=$(echo "$QA_SCREEN" | grep -c "alpha" || true)
if [[ "$count_after_undo" -eq 1 ]]; then
    qa_pass "undo removes the duplicated line"
else
    qa_fail "undo removes the duplicated line" "expected 1 'alpha' occurrence, found $count_after_undo"
fi

# Confirm the binding is also surfaced in the palette (Rule 2: UI
# discoverability) — not just a hidden keystroke.
qa_keys "ctrl-space"
qa_send "Duplicate Down" 0.3
qa_assert_expect '⌥U' "palette shows ⌥U shortcut for Duplicate Down"
qa_keys "escape"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
