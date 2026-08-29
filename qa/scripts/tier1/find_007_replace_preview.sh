#!/usr/bin/env bash
# QA-FIND-007: Replace shows live preview
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-007: Replace preview"

file=$(qa_tmpfile_nl "find007.txt" "foo bar foo
baz foo")
qa_start "$file"

# Open find and type search
qa_keys "ctrl-f"
qa_send "foo" 0.3

# Tab to replace field
qa_keys "tab"
qa_send "ZZZ"

# Should see preview of replacement in editor area
qa_assert_expect "ZZZ" "replace preview shows ZZZ"

# Escape should revert the preview (no changes saved)
qa_keys "escape"

qa_assert_expect "foo" "escape reverted replace preview"

qa_keys "ctrl-q"
qa_summary
