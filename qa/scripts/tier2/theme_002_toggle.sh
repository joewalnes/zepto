#!/usr/bin/env bash
# QA-THM-002: Toggle dark -> light theme and verify visual appearance
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
    "This should show a terminal text editor with a DARK theme (dark background, light text). Verify: (1) The background is dark (navy/black). (2) Syntax highlighting is visible with different colors for keywords, strings, and comments. (3) A status bar is visible at the bottom with pill-shaped buttons. (4) A tab bar is visible at the top." \
    "dark theme renders correctly"

# Toggle to light
qa_keys "ctrl-t"
sleep 0.3

shot_light="$QA_TMPDIR/light.png"
qa_screenshot "$shot_light"

qa_assert_visual "$shot_light" \
    "This should show the same terminal text editor but now with a LIGHT theme (white/cream background, dark text). Verify: (1) The background is light/white. (2) Syntax highlighting is still visible but with colors appropriate for a light background. (3) The tab bar at the top also uses light colors (NOT dark/navy). (4) The status bar at the bottom uses light colors." \
    "light theme renders correctly (including tab bar — regression check)"

# Toggle back to dark
qa_keys "ctrl-t"
sleep 0.3

shot_back="$QA_TMPDIR/back_to_dark.png"
qa_screenshot "$shot_back"

qa_assert_visual "$shot_back" \
    "This should show the editor back in DARK theme. Verify the background is dark again and all UI elements (tabs, status bar) are in dark theme colors." \
    "toggling back to dark works"

qa_keys "ctrl-q"

qa_summary
