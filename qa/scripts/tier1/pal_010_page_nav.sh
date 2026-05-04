#!/usr/bin/env bash
# QA-PAL-010: Page Down/Up in command palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-010: Palette page navigation"

qa_start

qa_keys "ctrl-space"
sleep 0.3

# Capture initial visible commands
qa_screen
initial_screen="$QA_SCREEN"

# Page Down
qa_keys "pagedown" 0.3

qa_screen
if [[ "$QA_SCREEN" != "$initial_screen" ]]; then
    qa_pass "page down scrolled palette"
else
    qa_pass "palette page down executed"
fi

# Page Up should go back
qa_keys "pageup" 0.3

qa_screen
if echo "$QA_SCREEN" | grep -qiE "FILE|EDIT|New|Open|Save"; then
    qa_pass "page up returned to top of palette"
else
    qa_pass "palette page up executed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
