#!/usr/bin/env bash
# QA-HELP-003: Changelog accessible from palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-HELP-003: Changelog"

qa_start

qa_keys "ctrl-space"
qa_send "changelog" 0.3

qa_assert_screen "Changelog|changelog" "changelog command visible in palette"

qa_keys "enter" 0.3

# Should show changelog content
qa_assert_screen "202[0-9]" "changelog shows dated entries"

qa_keys "ctrl-q"
qa_summary
