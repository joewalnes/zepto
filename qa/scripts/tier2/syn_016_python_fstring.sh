#!/usr/bin/env bash
# QA-SYN-016: Python f-string with {expr} highlighted
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-016: Python f-string highlighting (visual)"

file=$(qa_tmpfile_nl "syn016.py" '#!/usr/bin/env python3
name = "Alice"
age = 30
items = ["apple", "banana"]

# Simple f-string
greeting = f"Hello, {name}!"

# Expression in f-string
info = f"Next year {name} will be {age + 1}"

# Method call in f-string
upper = f"Name: {name.upper()}"

# Nested quotes
msg = f"Items: {', '.join(items)}"

# Regular string for comparison
plain = "This is a normal string"

print(greeting)
print(info)')
qa_start "$file"

shot="$QA_TMPDIR/python_fstring.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Python file in a terminal text editor with syntax highlighting. Verify: (1) f-strings (strings prefixed with f like f\"...\") are highlighted as strings. (2) The {expressions} inside f-strings are visually distinct from the surrounding string text — shown in a different color or style. (3) Regular strings without the f prefix are also highlighted. (4) At least 3 distinct colors are used across the file." \
    "Python f-string interpolation expressions highlighted"

qa_keys "ctrl-q"

qa_summary
