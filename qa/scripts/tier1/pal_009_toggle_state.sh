#!/usr/bin/env bash
# QA-PAL-009: Toggle commands show [on]/[off] state
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PAL-009: Toggle state display"

qa_start

qa_keys "ctrl-space"
qa_send "wrap" 0.3

# Should show [on] or [off] next to word wrap toggle
qa_assert_expect '\[(on|off)\]' "toggle state indicator visible"

qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
