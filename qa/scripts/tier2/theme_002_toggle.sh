#!/usr/bin/env bash
# QA-THM-002: Toggle dark -> light theme and verify
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-THM-002: Theme toggle (visual)"

file=$(qa_tmpfile_nl "theme002.py" "def hello():
    name = 'world'
    print(f'Hello, {name}!')
    return 42

# A comment about this function
class Foo:
    pass")
qa_start "$file"

# Capture dark theme screenshot
shot_dark="$QA_TMPDIR/dark.png"
qa_screenshot "$shot_dark"

qa_assert_visual "$shot_dark" \
    "This should show a terminal text editor with a DARK theme (dark background, light text). Verify: (1) The background is dark (navy/black). (2) Syntax highlighting is visible with different colors for keywords, strings, and comments. (3) A status bar is visible at the bottom. (4) A tab bar is visible at the top." \
    "dark theme renders correctly"

# Toggle to light via palette (ctrl-t intercepted by tmux)
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter"
sleep 0.3

# Verify toggle happened via palette text
qa_screen
if echo "$QA_SCREEN" | grep -q '\[light\]'; then
    qa_pass "theme toggled to light (palette confirms [light])"
else
    qa_fail "theme toggled to light"
fi

# Close palette
qa_keys "escape" 0.2
qa_keys "escape" 0.3

# Toggle back to dark
qa_keys "ctrl-space"
qa_send "theme" 0.3
qa_keys "enter"
sleep 0.3

qa_screen
if echo "$QA_SCREEN" | grep -q '\[dark\]'; then
    qa_pass "theme toggled back to dark (palette confirms [dark])"
else
    qa_fail "theme toggled back to dark"
fi

qa_keys "escape" 0.2
qa_keys "escape" 0.2
qa_keys "ctrl-q"

qa_summary
