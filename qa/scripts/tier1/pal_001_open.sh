#!/usr/bin/env bash
# QA-PAL-001: Ctrl+Space opens command palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-001: Ctrl+Space opens command palette"

file=$(qa_tmpfile_nl "pal001.txt" "hello")
qa_start "$file"

# Open palette (Ctrl+Space = NUL byte)
qa_keys "ctrl-space"

# Palette should show section headers or commands
qa_assert_screen "FILE|EDIT|NAVIGATE|VIEW|Commands" "palette visible with sections or title"

# Should see some commands
qa_assert_screen "Save|Quit|Find|Theme|Undo" "at least one known command visible"

# Close with Esc
qa_keys "escape"
sleep 0.2
qa_keys "escape" 0.2  # second esc in case first cleared filter

# Palette should be gone — main editor visible
qa_assert_screen "hello" "editor content visible after palette close"

qa_keys "ctrl-q"

qa_summary
