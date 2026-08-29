#!/usr/bin/env bash
# QA-REG-120: Tab Width shows an error message for invalid input
# Bug: the first implementation wrote validation errors to
# $self->{status_msg}, a field the renderer never reads (dead code —
# cmd_goto_line has the same latent bug, tracked separately in bugs.md).
# Invalid tab width input was silently rejected with no user-visible
# feedback. Fixed by using show_error_message(), the same API every other
# validated prompt in the editor uses.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-120: Tab Width invalid-input feedback"

file=$(qa_tmpfile_nl "reg120.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
qa_send "Tab Width" 0.3
qa_keys "enter" 0.2
qa_assert_expect "Tab Width: 4" "footer input opens prefilled with current value"

# Non-numeric input
qa_send "abc"
qa_keys "enter" 0.2
qa_assert_expect "Invalid tab width" "non-numeric input shows a visible error message"

# Out-of-range input (0)
qa_keys "ctrl-space"
qa_send "Tab Width" 0.3
qa_keys "enter" 0.2
qa_send "0"
qa_keys "enter" 0.2
qa_assert_expect "Invalid tab width" "out-of-range input (0) shows a visible error message"

# Out-of-range input (17)
qa_keys "ctrl-space"
qa_send "Tab Width" 0.3
qa_keys "enter" 0.2
qa_send "17"
qa_keys "enter" 0.2
qa_assert_expect "Invalid tab width" "out-of-range input (17) shows a visible error message"

# Preference must be untouched by all the rejected attempts
qa_keys "ctrl-space"
qa_send "Tab Width" 0.3
qa_keys "enter" 0.2
qa_assert_expect "Tab Width: 4" "tab width unchanged after rejected inputs"
qa_keys "escape" 0.2

qa_keys "ctrl-q"
qa_summary
