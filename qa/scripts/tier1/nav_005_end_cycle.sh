#!/usr/bin/env bash
# QA-NAV-005: End key cycles line end → doc end
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-NAV-005: End key cycling"

file=$(qa_tmpfile_nl "nav005.txt" "short
longer line here
end")
qa_start "$file"

# First End → end of line 1
qa_keys "end" 0.1
qa_assert_cursor_at 1:6 "End goes to end of line 1"

# Second End → end of document (line 3)
qa_keys "end" 0.1
qa_assert_cursor_at 3 "second End goes to last line"

qa_keys "ctrl-q"
qa_summary
