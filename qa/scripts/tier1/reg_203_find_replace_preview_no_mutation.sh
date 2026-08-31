#!/usr/bin/env bash
# QA-REG-203: Find & Replace preview never mutates the document or corrupts
# on-screen rendering
#
# bugs.md P0 "Find & Replace's 'preview' mutates the real document and
# corrupts on-screen rendering — despite being explicitly documented as
# non-mutating". Reported as three compounding symptoms from the exact
# repro this script reruns (⌃F, type "foo", Tab to replace, type a
# replacement, against a file with multiple "foo" matches each followed by
# more text on the same line):
#
#   1. Screen corruption: every replace-field keystroke left a stacked
#      duplicate row of the find/replace bar and preview lines instead of
#      overwriting in place.
#   2. Wrong preview text: showed "fooXYZ" instead of the correct
#      "XYZ bar" — concatenating the (unselected) prepopulated find term
#      with the typed replacement instead of substituting in place.
#   3. Claimed real document mutation via the undo stack.
#
# Root-cause investigation (see bugs.md's FIXED writeup for full detail)
# found symptoms 1 and 2 to be real, distinct root causes:
#   1. The find bar's replace-mode input-field width could be forced above
#      its actual layout budget on terminals narrower than ~90 cols
#      (confirmed: overflowed an 80-col terminal by 4 chars with a 3-match
#      count), wrapping onto the row below via the terminal's own
#      auto-wrap — which the differential renderer never accounts for or
#      clears. Fixed in Renderer.pm's new find_bar_input_width().
#   2. Tab-prepopulating the replace field with the find term didn't
#      pre-select it (unlike the find field's own prepopulation), so the
#      first keystroke appended instead of replacing. Fixed in
#      Editor.pm's Tab handler in handle_find_event.
# Symptom 3 (real mutation) did NOT reproduce under investigation — traced
# every call in the preview path (FindEngine.pm's preview_line/
# preview_viewport, Editor.pm's _apply_replace_preview) and confirmed all
# reads are via $doc->get_line_content() with no mutating calls anywhere
# in the preview path. This script still asserts the no-mutation guarantee
# directly (via the undo-stack "Nothing to undo" message) as a permanent
# regression guard, per bugs.md's convention of asserting the property
# even where the specific claimed bug didn't reproduce.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-203: Find & Replace preview — no mutation, no corruption, correct text"

file=$(qa_tmpfile_nl "reg203.txt" "foo bar
foo baz
qux foo
hello world")
qa_start "$file"
qa_assert_expect "foo bar" "file opened"

# --- Open find/replace, type the exact repro sequence ---------------------
qa_keys "ctrl-f"
qa_send "foo" 0.3
qa_assert_screen "3 of 3" "3 matches found for 'foo'"

qa_keys "tab"
qa_send "X" 0.3

# --- Symptom 2: correct in-place substitution, not concatenation ----------
qa_assert_screen "X bar" "preview shows 'X bar' after typing 'X' (not 'fooX')"
qa_assert_not_screen "fooX" "preview does NOT show 'fooX' (concatenation bug)"

qa_send "Y" 0.3
qa_send "Z" 0.3
qa_assert_screen "XYZ bar" "preview shows 'XYZ bar' (in-place substitution)"
qa_assert_screen "qux XYZ" "preview shows 'qux XYZ' (leading context preserved)"
qa_assert_not_screen "fooXYZ" "preview does NOT show 'fooXYZ' (concatenation bug)"

# --- Symptom 1: no stacked duplicate rows ----------------------------------
# After 3 keystrokes in the replace field, there must be exactly ONE
# find-bar row and exactly ONE occurrence of the current preview text on
# screen — not multiple stale copies stacked from earlier frames.
qa_screen
find_bar_rows=$(echo "$QA_SCREEN" | grep -c "Find:foo" || true)
if [[ "$find_bar_rows" -eq 1 ]]; then
    qa_pass "exactly one find-bar row on screen (no stacked duplicates)"
else
    qa_fail "exactly one find-bar row on screen (no stacked duplicates)" \
        "found $find_bar_rows rows matching 'Find:foo'"
fi

preview_rows=$(echo "$QA_SCREEN" | grep -c "XYZ bar" || true)
if [[ "$preview_rows" -eq 1 ]]; then
    qa_pass "exactly one 'XYZ bar' preview row on screen (no stacked duplicates)"
else
    qa_fail "exactly one 'XYZ bar' preview row on screen (no stacked duplicates)" \
        "found $preview_rows rows matching 'XYZ bar'"
fi

# --- Symptom 3: no real document mutation from the preview ----------------
# Escape (cancel) and wait past the terminal's ESC-key ambiguity timeout
# (0.5s -- a standalone ESC vs. the start of an Alt+key/escape sequence)
# before checking the settled screen.
qa_keys "escape" 1.0
qa_assert_expect "foo bar" "original content restored after Escape" 3
qa_assert_not_screen "XYZ" "no leftover 'XYZ' preview text after Escape"
qa_assert_not_screen "Find:" "find bar closed after Escape"

qa_keys "ctrl-z"
qa_assert_expect "Nothing to undo" "undo stack empty -- preview interaction pushed no real edits" 3

# --- Regression guard: real Replace-All (Enter) still works ---------------
qa_keys "ctrl-f"
qa_send "foo" 0.3
qa_keys "tab"
qa_send "REPL" 0.3
qa_keys "enter" 1.0
qa_assert_expect "Replaced 3 occurrences" "real Replace-All still works (Enter confirms)"
qa_assert_screen "REPL bar" "document actually shows the replacement"
qa_assert_screen "qux REPL" "document actually shows the replacement (line 3)"

# Undo Replace-All back to nothing -- each replaced match may be its own
# undo-group (implementation detail we don't want to hardcode a count for),
# so loop ctrl-z with a generous bound until the undo stack is empty.
undo_tries=0
while [[ $undo_tries -lt 10 ]]; do
    qa_screen
    if echo "$QA_SCREEN" | grep -q "Nothing to undo"; then
        break
    fi
    qa_keys "ctrl-z" 0.2
    undo_tries=$((undo_tries + 1))
done
qa_assert_expect "Nothing to undo" "Replace-All fully undoable back to original" 3
qa_assert_screen "foo bar" "original content restored after undoing Replace-All"

qa_keys "ctrl-q"
qa_summary
