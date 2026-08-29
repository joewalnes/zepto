#!/usr/bin/env bash
# QA-RCN-011: Recent files picker uses wider palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-RCN-011: Wide palette for recent files"

f1=$(qa_tmpfile_nl "rcn011_a.txt" "AAA")
f2=$(qa_tmpfile_nl "rcn011_b.txt" "BBB")

qa_start "$f1" "$f2"
qa_keys "alt-." 0.2

qa_keys "ctrl-e" 0.5

qa_assert_expect 'recent|rcn011' "recent picker rendered"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
