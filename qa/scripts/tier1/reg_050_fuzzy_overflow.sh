#!/usr/bin/env bash
# QA-REG-050: Fuzzy find input does not overflow with long query
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-050: Fuzzy find long query no overflow"

file=$(qa_tmpfile_nl "reg050.txt" "hello")
qa_start "$file"

# Open file picker
qa_keys "ctrl-o"
sleep 0.5

# Type a very long query
long_query="this_is_a_very_long_search_query_that_should_not_overflow_the_input_field_boundary"
qa_send "$long_query" 0.5

# Editor should not crash or display garbage
if qa_alive; then
    qa_pass "editor alive with long fuzzy find query"
else
    qa_fail "editor alive with long fuzzy find query" "editor crashed"
fi

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
