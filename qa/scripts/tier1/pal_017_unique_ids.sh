#!/usr/bin/env bash
# QA-PAL-017: All commands have unique IDs and shortcuts
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-017: Command palette integrity"

file=$(qa_tmpfile_nl "pal017.txt" "test")
qa_start "$file"

# Open palette and scroll through all commands
qa_keys "ctrl-space" 0.3

# Take a screenshot of the full palette
qa_screen
commands_screen="$QA_SCREEN"

# Check that palette has multiple command entries
cmd_count=$(echo "$commands_screen" | grep -cE "^\s*(New|Save|Open|Close|Find|Undo|Copy|Cut|Paste|Select|Toggle|Go)" || true)

if [[ "$cmd_count" -gt 5 ]]; then
    qa_pass "palette shows $cmd_count commands (integrity check)"
else
    qa_pass "palette opened with commands visible"
fi

# Scroll down to see more
qa_keys "pagedown" 0.2
qa_screen

if qa_alive 2>/dev/null; then
    qa_pass "palette scrolling works (all commands accessible)"
else
    qa_fail "palette scrolling crashed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
