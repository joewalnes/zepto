#!/usr/bin/env bash
# QA-REG-218: Toggling Light/Dark theme must not shift the status bar.
#
# Bug (found via direct user feedback while live-testing the editor):
# Renderer.pm's status-bar Theme pill concatenated the RAW toggle-display
# value ('dark'/'light'/'auto') onto its label with no width
# normalization -- unlike every other toggle command, which only ever
# displays the fixed-width 'on'/'off'. Since "light" is one character
# wider than "dark", switching themes shifted every pill rendered after
# the Theme pill by a column. At specific terminal widths (140 cols,
# confirmed live) this crossed the Word Wrap pill's priority-based
# visibility threshold entirely: dark showed the full "Word Wrap Z"
# label, light silently dropped to a bare "Z" glyph -- the same content,
# rendered inconsistently depending on which theme happened to be active.
# Fix: pad the theme display value to the width of the longest possible
# value ('light', 5 chars) so the Theme pill's width -- and therefore
# everything after it -- never depends on which theme is active.
# See bugs.md 2026-08-31, tests/renderer.t "Theme pill has constant
# width across dark/light/auto".
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-218: Theme toggle does not shift the status bar"

file=$(qa_tmpfile_nl "reg218.txt" "hello world")
qa_start "$file"

# 140 cols is the exact width confirmed live to cross the Word Wrap
# visibility threshold under the pre-fix bug.
qa_resize_window 140 24
sleep 0.3

qa_screen
before=$(echo "$QA_SCREEN" | tail -1)

qa_keys "ctrl-t"
sleep 0.3
qa_screen
after=$(echo "$QA_SCREEN" | tail -1)

# Strip the theme word AND the theme icon glyph (the icon deliberately
# differs -- moon vs sun -- that's correct, unrelated behavior, not part
# of this bug) before comparing -- everything ELSE on the status bar row
# must be byte-for-byte identical regardless of which theme is active.
before_stripped=$(printf '%s' "$before" | perl -CSD -pe 's/.\x20Theme:(dark|light)\x20+/X Theme:X /')
after_stripped=$(printf '%s' "$after" | perl -CSD -pe 's/.\x20Theme:(dark|light)\x20+/X Theme:X /')

if [[ "$before_stripped" == "$after_stripped" ]]; then
    qa_pass "status bar row is identical apart from the theme word after toggling (140 cols)"
else
    qa_fail "status bar row is identical apart from the theme word after toggling (140 cols)" \
        "before=[$before] after=[$after]"
fi

# 145 cols: Word Wrap's full label is visible in BOTH states (not just
# one) -- the more concrete "the label doesn't disappear depending on
# theme" regression guard.
qa_resize_window 145 24
sleep 0.3
qa_assert_screen "Word Wrap" "Word Wrap label visible after toggle at 145 cols (currently light)"

qa_keys "ctrl-t"
sleep 0.3
qa_assert_screen "Word Wrap" "Word Wrap label still visible after toggling back to dark at 145 cols"

qa_keys "ctrl-q"
qa_summary
