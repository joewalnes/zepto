#!/usr/bin/env bash
# QA-REG-142: Toggle confirmation messages don't inherit stale error styling
#
# Bug: show_message() correctly resets message_is_error => 0, but ~10
# preference-toggle commands in Editor/Commands.pm (cmd_toggle_autocomplete,
# cmd_toggle_auto_pairs, cmd_toggle_mouse, etc.) wrote $self->{message}
# directly instead of calling show_message(), bypassing the reset. If an
# error message was showing when one of these confirmations landed within
# the SAME input batch, the confirmation text inherited the error's red
# styling (Renderer.pm message row: message_is_error ? error_fg :
# warning_fg) even though it wasn't an error. Fixed by routing every
# direct assignment through show_message() (two similar sites in
# Editor.pm's replace-all message also fixed for consistency).
#
# NOTE on interactive repro: hangon drives zepto through separate process
# invocations, and each one reliably lands in its own read_blocking() /
# handle_input() batch -- Editor.pm's top-of-loop guard (~line 944) resets
# message_is_error before each of these keystrokes is processed, so
# sequential hangon commands cannot reproduce the exact same-batch race
# (that requires multiple input events to arrive in a single sysread()
# call, e.g. fast/pasted/scripted input -- not reliably controllable via
# hangon's one-command-per-key model; raw NUL bytes sent via
# `hangon send --stdin` were also found to not reproduce the ctrl-space
# palette shortcut the way `hangon keys ctrl-space` does, ruling out a
# simple single-write repro too).
#
# The same-batch race IS covered deterministically by the unit test
# "Toggle confirmation does not inherit stale error styling" in
# tests/editor.t, which calls show_error_message() then a toggle command
# directly -- bypassing run()'s per-batch guard entirely, exactly modeling
# "same batch". That test fails on unfixed code and passes after the fix.
#
# This script provides the baseline UI check instead: a real error message
# followed by a real toggle action (as two separate, sequential user
# actions) must still show the toggle confirmation in normal (non-error)
# styling -- i.e. the fix didn't break normal toggle messaging, and the
# color-selection logic itself (message_is_error ? error_fg : warning_fg)
# still works as expected end-to-end.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-142: Toggle confirmation does not inherit error styling"

file=$(qa_tmpfile_nl "reg142.txt" "hello")
qa_start "$file"

# --- Trigger a real, visible error message (invalid tab width) ------------
qa_keys "ctrl-space"
qa_send "Tab Width" 0.3
qa_keys "enter" 0.2
qa_send "abc"
qa_keys "enter" 0.2
qa_assert_expect "Invalid tab width" "error message is visible"

# Resolve the tmux target behind this hangon session (see reg_140 for the
# same pattern) so we can inspect the raw ANSI color codes on the message
# row -- qa_screen only gives us plain text, not styling.
holder=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
tmux_target="hangon-${holder}"

error_raw=$(tmux capture-pane -t "$tmux_target" -p -e 2>/dev/null | tail -1)
if echo "$error_raw" | grep -qE '38;2;(247;118;142|210;15;57)'; then
    qa_pass "error message renders with error_fg (red) color"
else
    qa_fail "error message renders with error_fg (red) color" "no error_fg escape found: $error_raw"
fi

# --- Immediately toggle a preference (a separate, sequential user action) -
qa_keys "ctrl-space"
qa_send "Auto Pairs" 0.3
qa_keys "enter" 0.3
qa_assert_expect "Auto Pairs:" "toggle confirmation message is visible"
qa_keys "escape" 0.2

toggle_raw=$(tmux capture-pane -t "$tmux_target" -p -e 2>/dev/null | tail -1)

if echo "$toggle_raw" | grep -qE '38;2;(247;118;142|210;15;57)'; then
    qa_fail "toggle confirmation is not styled as an error" "found error_fg (red) in: $toggle_raw"
else
    qa_pass "toggle confirmation is not styled as an error"
fi

if echo "$toggle_raw" | grep -qE '38;2;(224;175;104|223;142;29)'; then
    qa_pass "toggle confirmation uses warning_fg (normal message) color"
else
    qa_fail "toggle confirmation uses warning_fg (normal message) color" "no warning_fg escape found: $toggle_raw"
fi

qa_keys "ctrl-q"
qa_summary
