#!/usr/bin/env bash
# QA-HELP-002: About doc accessible from palette
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-HELP-002: About document"

qa_start

# Open palette and search for about
qa_keys "ctrl-space"
qa_send "about" 0.3

qa_assert_screen "About" "about command visible in palette"

qa_keys "enter" 0.3

# Should show about content with version info or project name
qa_assert_screen "Zepto|zepto|version|Version" "about document shows editor info"

qa_keys "ctrl-q"
qa_summary
