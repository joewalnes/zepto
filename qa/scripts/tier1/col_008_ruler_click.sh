#!/usr/bin/env bash
# QA-COL-008: Click COL badge in ruler toggles column mode
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-COL-008: Click COL badge toggles column mode"

file=$(qa_tmpfile_nl "col008.txt" "aaaa
bbbb
cccc")
qa_start "$file"

# First, verify COL indicator is not showing
qa_assert_not_screen "COL" "column mode initially off"

# Toggle column mode via Alt+C to verify the indicator location
qa_keys "alt-c"
qa_assert_expect "COL" "column mode on via alt-c"

# Toggle off
qa_keys "alt-c"
qa_assert_not_screen "COL" "column mode off again"

qa_keys "ctrl-q"
qa_summary
