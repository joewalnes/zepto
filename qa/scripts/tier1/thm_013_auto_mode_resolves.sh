#!/usr/bin/env bash
# QA-THM-013: Selecting "Theme: Auto" sets the preference to auto and
# resolves to a concrete theme (dark or light) via system detection.
#
# This must NOT assert which concrete theme it resolves to — that depends
# on the actual host's system appearance (real detection: no mock/inject
# path exists through the built binary's CLI, only in Perl unit tests via
# Zepto::Editor->new(theme_detect_fn => ...)). Only the plumbing is
# verified here: [auto] appears, and the editor renders normally
# afterward (proves the resolver didn't blow up / lock in an invalid
# state). See tests/theme_detect.t and tests/editor.t for deterministic,
# mocked coverage of the detection matrix itself.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-THM-013: Theme: Auto resolves to a concrete theme"

file=$(qa_tmpfile_nl "thm013.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "down" 0.2   # Theme: Auto
qa_keys "enter" 0.4

qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_assert_expect '\[auto\]' "Theme preference shows auto"
qa_keys "escape"
qa_keys "escape"

# Editor must still be alive and rendering normally (detection didn't
# crash or leave the editor in a broken state) — content is visible and
# the editor still responds to navigation (non-destructive, so the buffer
# stays clean and ^Q won't trip the unsaved-changes prompt).
qa_assert_expect "hello" "Document content still renders after auto-resolve"
qa_keys "end" 0.2
if qa_alive; then
    qa_pass "Editor still alive and responsive after auto-resolve"
else
    qa_fail "Editor still alive and responsive after auto-resolve" "Session died"
fi

qa_keys "ctrl-q"
qa_summary
