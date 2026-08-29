#!/usr/bin/env bash
# QA-CLI-001: Binary runs with no args — shows editor UI
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-001: Binary runs with no args"

qa_start

qa_assert_expect "1:1" "cursor position pill shows 1:1"
qa_assert_screen "Commands" "Commands pill visible"

qa_keys "ctrl-q"
qa_summary
