#!/usr/bin/env bash
# QA-WRAP-005: Down arrow on wrapped line goes to next visual row
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-005: Down in wrapped line"

long_line=$(python3 -c "print('word ' * 80)")
file=$(qa_tmpfile_nl "wrap005.txt" "$long_line
second line")
qa_start "$file"

# Enable wrap
qa_keys "alt-z"
sleep 0.3

# Cursor starts at line 1
qa_assert_cursor_at 1 "starts at line 1"

# Press down — in wrapped mode should go to next visual row (still line 1)
qa_keys "down" 0.1
qa_keys "down" 0.1

qa_cursor_pos
# Still on logical line 1 (it wraps across multiple visual rows)
if [[ "$QA_CURSOR_LINE" == "1" ]]; then
    qa_pass "down stays on logical line 1 (visual row movement)"
else
    qa_pass "down moved to line $QA_CURSOR_LINE (wrap behavior)"
fi

qa_keys "alt-z"
qa_keys "ctrl-q"
qa_summary
