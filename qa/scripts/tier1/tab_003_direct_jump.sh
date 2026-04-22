#!/usr/bin/env bash
# QA-TAB-003: Direct tab jump with Alt+1-9
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-003: Direct tab jump Alt+N"

file1=$(qa_tmpfile_nl "tab003_a.txt" "content A")
file2=$(qa_tmpfile_nl "tab003_b.txt" "content B")
file3=$(qa_tmpfile_nl "tab003_c.txt" "content C")
qa_start "$file1" "$file2" "$file3"

# Jump to tab 3 (Alt+3 = ESC 3)
qa_raw $'\x1b3' 0.3
qa_assert_screen "content C" "alt-3 shows tab 3"

# Jump to tab 1
qa_raw $'\x1b1' 0.3
qa_assert_screen "content A" "alt-1 shows tab 1"

# Jump to tab 2
qa_raw $'\x1b2' 0.3
qa_assert_screen "content B" "alt-2 shows tab 2"

qa_keys "ctrl-q"
qa_summary
