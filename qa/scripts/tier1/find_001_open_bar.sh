#!/usr/bin/env bash
# QA-FIND-001: Ctrl+F opens find bar
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-001: Ctrl+F opens find bar"

file=$(qa_tmpfile_nl "find001.txt" "hello world
foo bar baz
hello again")
qa_start "$file"

# Open find
qa_keys "ctrl-f"

# Find bar should be visible — look for indicators
qa_assert_expect "Esc|Find|Aa" "find bar visible (Esc/Find/Aa indicator)"

# Type a query
qa_send "hello"
sleep 0.3

# Should show match count
qa_assert_expect "[12] of [12]|2|matches" "match count visible (2 matches expected)"

# Close find — press Escape twice (first may clear query, second closes bar)
qa_keys "escape"
sleep 0.2
qa_keys "escape"

# After find bar is closed, status bar should show normal pills
qa_assert_expect "hello" "editor content visible after find close"

qa_keys "ctrl-q"
qa_summary
