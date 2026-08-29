#!/usr/bin/env bash
# QA-NAV-001: Arrow keys move cursor
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-001: Arrow key navigation"

file=$(qa_tmpfile_nl "nav001.txt" "abcdef
ghijkl
mnopqr")
qa_start "$file"

qa_assert_expect "1:1" "starts at 1:1"

qa_keys "right" 0.1
qa_keys "right" 0.1
qa_keys "right" 0.1
qa_assert_expect "1:4" "right x3 = col 4"

qa_keys "down" 0.1
qa_assert_expect "2:4" "down = line 2"

qa_keys "left" 0.1
qa_assert_expect "2:3" "left = col 3"

qa_keys "up" 0.1
qa_assert_expect "1:3" "up = line 1"

qa_keys "ctrl-q"
qa_summary
