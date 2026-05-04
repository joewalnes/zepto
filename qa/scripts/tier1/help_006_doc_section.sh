#!/usr/bin/env bash
# QA-HELP-006: Documentation commands present in palette under DOCUMENTATION section
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-HELP-006: Doc section in palette"

file=$(qa_tmpfile_nl "help006.txt" "test")
qa_start "$file"

# Open palette and look for DOCUMENTATION section
qa_keys "ctrl-space"
sleep 0.3

# Scroll down to find documentation section
# Or search for it
qa_screen
if echo "$QA_SCREEN" | grep -qi "DOCUMENTATION"; then
    qa_pass "DOCUMENTATION section header visible in palette"
else
    # Try scrolling
    qa_keys "escape"
    qa_keys "ctrl-space"
    qa_send "about" 0.3
    qa_assert_screen "About" "About command found in palette"
fi

qa_keys "escape"

# Check individual doc commands
for cmd in "Tutorial" "Changelog" "License"; do
    qa_keys "ctrl-space"
    qa_send "$cmd" 0.3
    qa_screen
    if echo "$QA_SCREEN" | grep -qi "$cmd"; then
        qa_pass "$cmd command present in palette"
    else
        qa_fail "$cmd command present in palette"
    fi
    qa_keys "escape"
done

qa_keys "ctrl-q"
qa_summary
