#!/usr/bin/env bash
# QA-PAL-022: Page Down/Up in command palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-022: Palette Page Down/Up"

file=$(qa_tmpfile_nl "pal022.txt" "hello")
qa_start "$file"

qa_keys "ctrl-space"
sleep 0.3

# Page Down
qa_keys "pagedown"
sleep 0.3

# Page Up
qa_keys "pageup"
sleep 0.3

# Should still be in palette, responsive
qa_assert_screen "Commands" "palette still open after Page Down/Up"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
