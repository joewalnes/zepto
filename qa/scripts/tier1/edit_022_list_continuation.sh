#!/usr/bin/env bash
# QA-EDIT-022: Enter continues Markdown/plain-text list items
#
# bugs.md "Markdown/plain-text list continuation" (Phase 2 item 5):
# Editor::do_enter now continues `-`/`*`/`+` bullets, `> ` blockquotes,
# `- [ ] `/`- [x] ` checkboxes (always continuing unchecked), and
# `N.`/`N)` numbered lists (incrementing) when Enter is pressed at the
# end of a non-empty item; pressing Enter on an EMPTY item removes the
# marker instead (escapes the list). Gated on the `continue_lists` pref
# (default on) and Markdown/plain-text file type only.
#
# Uses qa_send_safe (not qa_send) for every string starting with '-' —
# see bugs.md "[Testing hazard] hangon's send fails outright on text
# starting with a hyphen". A plain qa_send here would silently abort the
# whole script under set -e.
#
# Screen layout: row 1 = tab bar, row 2 = ruler, row 3 = doc line 1,
# row (2+N) = doc line N.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-EDIT-022: List continuation on Enter"

# .txt is one of the prose extensions that count as "plain text" for
# list continuation (Markdown or no-grammar-detected).
file=$(qa_tmpfile_nl "edit022.txt" "")
qa_start "$file"

# --- Dash bullet continues (doc line 1 -> line 2) ---
qa_send_safe "- first item"
qa_keys "enter"
sleep 0.2
# NOTE: hangon's screen capture trims trailing whitespace per row, so the
# marker's trailing space (e.g. "- ") is never visible here — match on
# the marker character only, and confirm no leftover content follows it.
qa_screen
line2=$(printf '%s' "$QA_SCREEN" | sed -n '4p')
if [[ "$line2" == *"-"* && "$line2" != *"item"* ]]; then
    qa_pass "new line gets the same dash marker, with no leftover content"
else
    qa_fail "new line missing the continued dash marker" "$line2"
fi

# --- Enter on the now-empty marker (line 2) escapes the list ---
qa_keys "enter"
sleep 0.2
qa_screen
line2_after=$(printf '%s' "$QA_SCREEN" | sed -n '4p')
line3_after=$(printf '%s' "$QA_SCREEN" | sed -n '5p')
if [[ "$line2_after" != *"-"* && "$line3_after" != *"-"* ]]; then
    qa_pass "empty list item escaped — marker removed, no dash left on either line"
else
    qa_fail "empty list item did not escape the list as expected" "line2=[$line2_after] line3=[$line3_after]"
fi

# --- Numbered list increments (doc line 3 -> line 4) ---
qa_send "1. numbered item"
qa_keys "enter"
sleep 0.2
qa_screen
line4=$(printf '%s' "$QA_SCREEN" | sed -n '6p')
if [[ "$line4" == *"2."* && "$line4" != *"item"* ]]; then
    qa_pass "numbered marker increments (1. -> 2.)"
else
    qa_fail "numbered marker did not increment" "$line4"
fi

# Escape the numbered list too, to get to a clean line for the next case.
qa_keys "enter"
sleep 0.2

# --- Checkbox always continues unchecked (doc line 5 -> line 6) ---
qa_send_safe "- [x] a done task"
qa_keys "enter"
sleep 0.2
qa_screen
line6=$(printf '%s' "$QA_SCREEN" | sed -n '8p')
if [[ "$line6" == *"[ ]"* && "$line6" != *"task"* ]]; then
    qa_pass "checked checkbox continues as unchecked '- [ ] '"
else
    qa_fail "checkbox did not continue as unchecked" "$line6"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
