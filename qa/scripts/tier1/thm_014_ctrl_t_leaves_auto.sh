#!/usr/bin/env bash
# QA-THM-014: ^T while the theme preference is 'auto' switches to the
# explicit opposite of whatever is currently effective, and LEAVES auto
# mode (the preference becomes an explicit dark/light, not auto again).
# Re-entering auto requires the dedicated "Theme: Auto" palette command.
#
# The specific resulting dark/light value is host-dependent (real system
# detection — see QA-THM-013's comment), so this only asserts the
# host-independent part of the contract: before ^T the indicator reads
# [auto]; after ^T it reads [dark] or [light], never [auto] again.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-THM-014: ^T leaves auto mode"

file=$(qa_tmpfile_nl "thm014.txt" "hello")
qa_start "$file"

# Enter auto mode
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "down" 0.2   # Theme: Auto
qa_keys "enter" 0.4

qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_assert_expect '\[auto\]' "Starts in auto mode"
qa_keys "escape"
qa_keys "escape"

# ^T must leave auto mode
qa_keys "ctrl-t" 0.4
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -qE '\[(dark|light)\]'; then
    qa_pass "^T set an explicit dark/light preference"
else
    qa_fail "^T set an explicit dark/light preference" "Screen: $QA_SCREEN"
fi
if echo "$QA_SCREEN" | grep -qE '\[auto\]'; then
    qa_fail "^T left auto mode" "Still shows [auto] after ^T"
else
    qa_pass "^T left auto mode"
fi
qa_keys "escape"
qa_keys "escape"

# A second ^T toggles normally between the two explicit values (no
# stickiness back to auto — auto is only re-entered via the palette).
qa_keys "ctrl-t" 0.4
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_assert_not_screen '\[auto\]' "Second ^T still not auto"
qa_keys "escape"
qa_keys "escape"

qa_keys "ctrl-q"
qa_summary
