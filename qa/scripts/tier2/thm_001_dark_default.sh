#!/usr/bin/env bash
# QA-THM-001: Fresh start shows dark theme
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-THM-001: Default dark theme (visual)"

file=$(qa_tmpfile_nl "thm001.py" 'import os

# A sample function
def calculate(x, y):
    """Multiply two numbers."""
    result = x * y
    return result

class Config:
    debug = True
    name = "default"
    max_items = 50

if __name__ == "__main__":
    val = calculate(6, 7)
    print(f"Result: {val}")')
qa_start "$file"

shot="$QA_TMPDIR/dark_default.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a terminal text editor on a fresh start (default settings). Verify ALL of these about the DARK THEME: (1) The main editing area has a DARK background color (black, very dark blue, or very dark gray). (2) The text/code is in LIGHT colors — readable against the dark background. (3) The status bar at the bottom has a dark or contrasting background. (4) The tab bar at the top has a dark background. (5) Syntax highlighting colors (for keywords, strings, comments) are bright/vivid colors on the dark background. (6) The overall appearance is unmistakably a 'dark theme' — dark background with light foreground text throughout." \
    "Fresh start shows dark theme with dark background and light text"

qa_keys "ctrl-q"

qa_summary
