#!/usr/bin/env bash
# QA-CPLT-020: Completion doesn't interfere with paste
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CPLT-020: Paste doesn't trigger cascading completion"

file=$(qa_tmpfile_nl "cplt020.js" "const longVariableName = 1
")
qa_start "$file"

# Move to line 2
qa_keys "down"

# Type text, copy it, clear, paste back
qa_send "some pasted text here"
qa_keys "ctrl-a"
qa_keys "ctrl-c"
qa_keys "ctrl-a"
qa_keys "ctrl-v"
sleep 0.5

# Paste should go through cleanly
qa_assert_expect "some pasted text here" "paste completed without interference"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
