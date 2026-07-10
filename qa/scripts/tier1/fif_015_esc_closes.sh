#!/usr/bin/env bash
# QA-FIF-015: Esc closes find-in-files palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-015: Esc closes find-in-files"

file=$(qa_tmpfile_nl "fif015.txt" "hello world")
qa_start "$file"

# Open find-in-files
qa_keys "ctrl-f"
sleep 0.2
# Switch to find-in-files with ctrl-shift-f might not work; use palette approach
qa_keys "escape"
qa_keys "ctrl-space"
qa_send "find in files" 0.3
qa_keys "enter"
sleep 0.5

qa_send "hello" 0.3

# Settle before sending Escape as its own, cleanly separated keystroke.
# On slow/loaded runners, if Escape arrives glued to the tail of "hello" in
# the same read, the terminal state may not have caught up with what we
# just typed yet — wait for "hello" to actually land in the FIF input
# first so Escape is sent against settled state, not raced against it.
qa_expect_screen "hello" 5 -F || true

# Press Esc to close
qa_keys "escape"

# Poll for the panel to actually close instead of a fixed sleep — more
# robust under load, and faster than a fixed sleep on a healthy run.
qa_expect_screen "hello world" 5 -F || true

# Should be back to editor
qa_assert_screen "hello world" "editor visible after closing FIF"

qa_keys "ctrl-q"
qa_summary

# ---------------------------------------------------------------------------
# TEMP-DEBUG (remove after CI diagnosis of the ^[-in-query failure).
# Runs only when the assertion above failed AND we're on CI.
# ---------------------------------------------------------------------------
if [ "${CI:-}" = "true" ] && ! qa_screen | grep -qF "hello world"; then
    echo "=== TEMP-DEBUG fif_015 ==="
    echo "--- versions ---"
    tmux -V; command -v hangon; hangon version 2>/dev/null || hangon --version 2>/dev/null || echo "no version cmd"
    echo "--- tmux escape-time / assume-paste-time ---"
    tmux show-options -g -s escape-time 2>/dev/null; tmux show-options -g assume-paste-time 2>/dev/null
    echo "--- screen (plain) ---"; qa_screen
    echo "--- input row hexdump ---"
    qa_screen | grep -n "hello" | head -2 | od -c | head -6
    echo "--- probe 1: hangon keys escape again after 1s ---"
    sleep 1; hangon keys "$QA_SESSION" escape; sleep 1
    qa_screen | head -6
    echo "--- probe 2: raw ESC byte via tmux send-keys -H 1b ---"
    pid=$(hangon info "$QA_SESSION" 2>/dev/null | grep -oE 'PID=[0-9]+' | cut -d= -f2)
    [ -z "$pid" ] && pid=$(hangon list 2>/dev/null | grep -oE '[0-9]+' | head -1)
    for t in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep hangon); do
        tmux send-keys -t "$t" -H 1b 2>/dev/null && echo "sent raw 1b to $t"
    done
    sleep 1; qa_screen | head -6
    echo "=== END TEMP-DEBUG ==="
fi
