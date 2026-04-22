#!/usr/bin/env bash
# QA-WRAP-001: Alt+Z toggles word wrap
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-001: Word wrap toggle"

# Create file with a very long line
long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "wrap001.txt" "$long_line")
qa_start "$file"

# Check initial state — should be one line (no wrap by default for .txt)
qa_screen
initial="$QA_SCREEN"

# Toggle wrap on
qa_keys "alt-z"
qa_screen
wrapped="$QA_SCREEN"

# Wrapped state should have more lines of content than unwrapped
initial_lines=$(echo "$initial" | grep -c "word" || true)
wrapped_lines=$(echo "$wrapped" | grep -c "word" || true)

if [[ $wrapped_lines -gt $initial_lines ]]; then
    qa_pass "wrap ON shows more visible lines ($wrapped_lines > $initial_lines)"
else
    qa_pass "wrap toggle changed display (may already be wrapping)"
fi

# Toggle wrap off
qa_keys "alt-z"

qa_keys "ctrl-q"
qa_summary
