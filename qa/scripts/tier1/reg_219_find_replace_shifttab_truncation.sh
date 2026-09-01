#!/usr/bin/env bash
# QA-REG-219: Shift+Tab in the find/replace bar no longer truncates the
# Find and Replace field display
#
# bugs.md P2 "Shift+Tab in the find/replace bar drops the last character of
# BOTH the Find and Replace field values" -- found while independently
# re-verifying the Replace-mode-indicator fix (QA-REG-217): ^F -> type "aaa"
# -> Tab to replace field -> type "bbb" -> raw Shift+Tab (CSI Z) to toggle
# replace mode, and BOTH "Find:aaa" and "Rep One:bbb" rendered with their
# trailing character missing ("aa"/"bb"), 100% reproducible.
#
# Root cause (traced with temporary debug instrumentation, not guessed):
# NOT InputParser.pm -- CSI-Z parsing was confirmed to produce exactly one
# correct key=tab,modifiers=[shift] event per raw Shift+Tab byte sequence,
# no stray bytes. The real bug is in Zepto::InputWidget's viewport()
# (lib/Zepto/InputWidget.pm), which caches its horizontal scroll offset
# (view_offset) across render calls. Shift+Tab calls
# Editor.pm's _update_find_matches(1), which leaves the find engine's
# is_searching flag momentarily true for exactly one render frame; while
# true, Renderer.pm's _render_find_bar appends "..." to the match-count
# text, which shrinks the shared find/replace input_width for that one
# frame (find_bar_input_width() divides the narrower budget across both
# fields). With "aaa"/"bbb" both exactly as wide as that transiently
# narrowed field and the cursor at the end, viewport()'s scroll-into-view
# check fires and bumps view_offset from 0 to 1. On the very next frame,
# is_searching goes false and the field widens back out to fit the whole
# value again -- but the stale view_offset=1 was never reset, because the
# cursor still fit inside the [view_offset, view_offset+width) window
# under the wider width too, so nothing re-triggered a correction. The
# field then permanently rendered with its first character scrolled out
# of view, even though $self->{value} itself was never touched.
#
# Fix: viewport() now resets view_offset to 0 whenever the caller-supplied
# width is wide enough to show the entire value ($len <= $width), instead
# of trusting a cached offset from a previous (possibly narrower) call.
# This only applies when the whole value fits; the deliberate "one empty
# trailing cell at cursor" scroll behavior for values genuinely longer
# than the field (tests/input_widget.t's existing 'viewport scrolls to
# keep cursor visible when at end') is untouched.
#
# Since the bug lives in the shared InputWidget (not find-bar-specific
# code), it could in principle affect any status-bar text field whose
# width narrows for a single transient frame while the cursor sits at the
# boundary -- Go To Line, Save As, the command palette filter. This script
# exercises the exact find-bar repro from bugs.md; tests/input_widget.t
# and tests/renderer.t cover the general InputWidget/Renderer mechanism
# directly (including a regression guard that the long-value "empty
# trailing cell" scroll behavior is unaffected by this fix).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-219: Find/replace bar Shift+Tab does not truncate field values"

file=$(qa_tmpfile_nl "reg218.txt" "aaa bbb ccc
aaa aaa aaa")
qa_start "$file"

# --- Set up: find "aaa", tab to replace field, type "bbb" ----------------
qa_keys "ctrl-f"
qa_send "aaa" 0.3
qa_keys "tab"
sleep 0.3
qa_send "bbb" 0.3

qa_assert_screen "Find:aaa" "before Shift+Tab: find field shows full 'aaa'"
qa_assert_screen "Rep All:bbb" "before Shift+Tab: replace field shows full 'bbb'"

# --- Raw Shift+Tab (CSI Z) toggles replace mode -- not in hangon's named
# `keys` list, raw CSI injection is the established technique used by
# QA-REG-217's script for the same key. -------------------------------------
printf '\x1b[Z' | qa_raw_stdin
sleep 0.5

# --- The actual bug: BOTH fields used to drop their trailing character ---
qa_assert_screen "Find:aaa" "after Shift+Tab: find field still shows full 'aaa' (not truncated to 'aa')"
qa_assert_not_screen "Find:aa " "after Shift+Tab: find field is not truncated to 'aa'"
qa_assert_screen "Rep One:bbb" "after Shift+Tab: replace field still shows full 'bbb' (not truncated to 'bb'), and mode toggled to Rep One"
qa_assert_not_screen "Rep One:bb " "after Shift+Tab: replace field is not truncated to 'bb'"

# --- Mode toggle itself still works (this is a display-corruption fix,
# not a toggle-logic fix -- cycle all the way back to Replace All and
# confirm values remain intact throughout) ----------------------------------
for _ in 1 2 3 4 5; do
    printf '\x1b[Z' | qa_raw_stdin
    sleep 0.3
done

qa_assert_screen "Rep All:" "full Shift+Tab cycle (5 more presses) returns to Replace All mode"
qa_assert_screen "Find:aaa" "find field still intact after a full Shift+Tab cycle"
qa_assert_screen "Rep All:bbb" "replace field still intact after a full Shift+Tab cycle"

# --- Same repro with a different-length term, to confirm this isn't
# specific to exactly 3-character values. Deliberately short (2 chars,
# not 5+): the find bar's input field is only ~3-4 columns wide at an
# 80-col terminal with the replace field also showing (see
# find_bar_input_width()), so a longer term would legitimately scroll
# regardless of this fix -- that's correct overflow behavior (see
# tests/input_widget.t's "does not disturb legitimate end-of-value
# scroll for long values"), not the bug under test here. -------------------
qa_keys "escape"
sleep 0.5
qa_keys "ctrl-f"
qa_send "hi" 0.3
qa_keys "tab"
sleep 0.3
qa_send "ok" 0.3
qa_assert_screen "Find:hi" "second repro (2-char term): find field shows full 'hi' before Shift+Tab"
qa_assert_screen "Rep All:ok" "second repro: replace field shows full 'ok' before Shift+Tab"

printf '\x1b[Z' | qa_raw_stdin
sleep 0.5

qa_assert_screen "Find:hi" "second repro: find field still shows full 'hi' after Shift+Tab"
qa_assert_screen "Rep One:ok" "second repro: replace field still shows full 'ok' after Shift+Tab, mode toggled"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
