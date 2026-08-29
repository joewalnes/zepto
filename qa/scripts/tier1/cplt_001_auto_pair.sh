#!/usr/bin/env bash
# QA-CPLT-001+002+003+004: Auto-pair brackets and quotes
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-001: Auto-pair brackets"

file=$(qa_tmpfile "cplt001.js" "")
qa_start "$file"

# Auto-pairs is ON by default (each test gets fresh state dir)
sleep 0.3

# Type opening paren
qa_send "("
qa_assert_expect "\\(\\)" "( auto-paired to ()"

# Type opening brace
qa_keys "end"
qa_send "{"
qa_assert_expect "\\{\\}" "{ auto-paired to {}"

# Type opening bracket
qa_keys "end"
qa_send "["
qa_assert_expect "\\[\\]" "[ auto-paired to []"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
