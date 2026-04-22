#!/usr/bin/env bash
# QA-FIND-006: Replace All replaces every match
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIND-006: Replace All"

file=$(qa_tmpfile_nl "find006.txt" "foo bar foo
baz foo qux
foo end")
qa_start "$file"

# Open find
qa_keys "ctrl-f"
qa_send "foo" 0.3

# Tab to replace field
qa_keys "tab" 0.2

# Select all in replace field and type replacement
qa_keys "ctrl-a" 0.1
qa_send "ZZZ" 0.3

# Enter commits the replacement
qa_keys "enter"
sleep 0.3

# Close find bar and save
qa_keys "escape"
qa_keys "ctrl-s"

# Check file on disk
qa_assert_file_not_contains "$file" "foo" "no 'foo' remaining in file"
qa_assert_file_contains "$file" "ZZZ bar ZZZ" "replacements present in file"

qa_keys "ctrl-q"
qa_summary
