#!/usr/bin/env bash
# QA-THM-002: Ctrl-T toggles dark to light theme
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-THM-002: Toggle to light theme (visual)"

file=$(qa_tmpfile_nl "thm002.py" 'import os

# A comment
def hello(name):
    """Docstring."""
    msg = "Hello " + name
    return msg

count = 42
active = True')
qa_start "$file"

# Toggle to light
qa_keys "ctrl-t"
sleep 0.3

shot="$QA_TMPDIR/thm002.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor after toggling to LIGHT theme. Verify: (1) The main editing area has a LIGHT/WHITE background. (2) Text is DARK on the light background. (3) The tab bar, status bar, and gutter all use light-colored backgrounds — no dark remnants." \
    "Light theme active with white background and dark text"

# Toggle back to dark
qa_keys "ctrl-t"
qa_keys "ctrl-q"

qa_summary
