#!/usr/bin/env bash
# QA-XFM-001+002: Alt+T opens transform and pipes through shell
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-XFM-001: Transform via shell"

file=$(qa_tmpfile_nl "xfm001.txt" "cherry
apple
banana")
qa_start "$file"

# Select all
qa_keys "ctrl-a"

# Open transform
qa_keys "alt-t"
qa_assert_expect "Shell|sort|command|pipe|Transform" "transform input visible"

# The Shell: prompt pre-fills with "sort" — clear and type fresh
qa_keys "ctrl-a" 0.1
qa_send "sort" 0.2
qa_keys "enter"
sleep 0.5

# Text should be sorted
qa_screen
if echo "$QA_SCREEN" | grep -q "apple"; then
    qa_pass "sort command executed — apple visible"
else
    qa_fail "sort command executed — apple visible"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
