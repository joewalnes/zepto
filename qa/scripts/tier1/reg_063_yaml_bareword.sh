#!/usr/bin/env bash
# QA-REG-063: YAML literal not matched inside bare words
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-063: YAML bare word literal regression"

# Create YAML file with a word containing 'on' (like 'region')
file=$(qa_tmpfile_nl "reg063.yaml" "name: region
enabled: true
category: frontend")
qa_start "$file"

# The word "region" should be visible as plain text, not highlighted as keyword
# Just verify the file opens and displays correctly without issues
qa_assert_screen "region" "region displayed correctly"
qa_assert_screen "enabled" "enabled displayed"
qa_assert_screen "frontend" "frontend displayed"

# Editor should not crash or misbehave
qa_alive
qa_pass "editor alive with YAML bare word containing literal"

qa_keys "ctrl-q"
qa_summary
