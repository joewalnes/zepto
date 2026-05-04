#!/usr/bin/env bash
# QA-TAB-006+007: Alt+. next tab, Alt+, prev tab
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TAB-006: Next/prev tab"

file1=$(qa_tmpfile_nl "tab006_a.txt" "AAA_content")
file2=$(qa_tmpfile_nl "tab006_b.txt" "BBB_content")
file3=$(qa_tmpfile_nl "tab006_c.txt" "CCC_content")
qa_start "$file1" "$file2" "$file3"

# Should start on tab 1
qa_assert_screen "AAA_content" "starts on tab 1"

# Next tab (Alt+.)
qa_keys "alt-."
qa_assert_screen "BBB_content" "alt-. moved to tab 2"

# Next tab again
qa_keys "alt-."
qa_assert_screen "CCC_content" "alt-. moved to tab 3"

# Prev tab (Alt+,)
qa_keys "alt-,"
qa_assert_screen "BBB_content" "alt-, moved back to tab 2"

# Prev tab again
qa_keys "alt-,"
qa_assert_screen "AAA_content" "alt-, moved back to tab 1"

qa_keys "ctrl-q"
qa_summary
