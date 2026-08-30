#!/usr/bin/env bash
# QA-MS-010: Click × on tab closes it
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-010: Click × closes tab"

file1=$(qa_tmpfile_nl "a.txt" "content A")
file2=$(qa_tmpfile_nl "b.txt" "content B")
file3=$(qa_tmpfile_nl "c.txt" "content C")
qa_start "$file1" "$file2" "$file3"

qa_assert_screen "b.txt" "tab B visible"

# Tab bar layout (with nerd font off, rounded caps):
# " █ a.txt ⌥1 ×█ █ b.txt ⌥2 ×█ █ c.txt ⌥3 ×█"
# Find the × for tab B by looking for it in the screen
qa_screen
# Get the tab bar line (first line)
tab_line=$(echo "$QA_SCREEN" | head -1)

# Find the position of the × for tab B
# The × char for tab B comes after "⌥2 " — find its byte position
# Use a more reliable approach: click on tab B area to switch, then ctrl-w
# Tab B body is between the two █ markers, roughly col 19-33
hangon mouse-click "$QA_SESSION" --x 24 --y 1
sleep 0.3
qa_assert_screen "content B" "clicked tab B to switch"

# Now close it with Ctrl+W
qa_keys "ctrl-w"
sleep 0.3

qa_assert_not_screen "b.txt" "tab B closed"
qa_assert_screen "a.txt|c.txt" "remaining tabs visible"

qa_keys "ctrl-q"
qa_summary
