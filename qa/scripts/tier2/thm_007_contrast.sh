#!/usr/bin/env bash
# QA-THM-007: Contrast sufficient in both themes
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-THM-007: Theme contrast verification (visual)"

file=$(qa_tmpfile_nl "thm007.py" '# Comment line
def calculate(x, y):
    """A docstring."""
    result = x * y  # inline comment
    name = "hello"
    count = 42
    return result

if True:
    print("done")')
qa_start "$file"

# Dark theme screenshot
shot_dark="$QA_TMPDIR/thm007_dark.png"
qa_screenshot "$shot_dark"

qa_assert_visual "$shot_dark" \
    "This shows a Python file in DARK theme. Verify: (1) ALL text elements are clearly readable — no text blends into the background. (2) Comments, strings, keywords, and numbers are each distinguishable. (3) At least 3 distinct colors are visible in the code." \
    "Dark theme has sufficient contrast for all elements"

# Light theme screenshot
qa_keys "ctrl-t"
sleep 0.3

shot_light="$QA_TMPDIR/thm007_light.png"
qa_screenshot "$shot_light"

qa_assert_visual "$shot_light" \
    "This shows a Python file in LIGHT theme. Verify: (1) ALL text elements are clearly readable on the white/light background. (2) Comments, strings, keywords, and numbers are each distinguishable. (3) At least 3 distinct colors are visible in the code." \
    "Light theme has sufficient contrast for all elements"

qa_keys "ctrl-t"
qa_keys "ctrl-q"

qa_summary
