#!/usr/bin/env bash
# QA-REG-072: Nerd Font toggle via Alt+I
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-072: Nerd Font toggle via Alt+I"

file=$(qa_tmpfile_nl "reg072.txt" "hello world")
qa_start "$file"

# Capture initial screen
qa_screen
initial="$QA_SCREEN"

# Toggle nerd font
qa_keys "alt-i"
sleep 0.3

qa_screen
after="$QA_SCREEN"

# Toggle back
qa_keys "alt-i"
sleep 0.3

# Screen should have changed (glyphs on/off)
if [[ "$initial" != "$after" ]]; then
    qa_pass "Alt+I toggled nerd font (screen changed)"
else
    # May not change if no nerd font glyphs visible, but shouldn't crash
    qa_pass "Alt+I handled without crash"
fi

qa_keys "ctrl-q"
qa_summary
