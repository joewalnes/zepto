#!/usr/bin/env bash
# QA-MS-023: Mouse wheel scroll-down clamps so the last line stays pinned
# at the bottom of the viewport, instead of letting it rise to the top and
# leaving the rest of the viewport blank (REGRESSION).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-MS-023: Scroll wheel clamps at end of file"

content=""
for i in $(seq 1 200); do content+="line $i"$'\n'; done
file=$(qa_tmpfile_nl "ms023.txt" "$content")
qa_start "$file"

qa_assert_expect "1:1" "editor loaded"

# Scroll drastically past the end of the 200-line file with the mouse wheel.
hangon mouse-scroll "$QA_SESSION" --x 10 --y 10 --delta 500
sleep 0.4
qa_screen

if echo "$QA_SCREEN" | grep -qF "line 200"; then
    qa_pass "last line (200) is visible after scrolling past the end"
else
    qa_fail "last line (200) is visible after scrolling past the end" "$QA_SCREEN"
fi

# The last non-status-bar screen row should be the last line of the
# document, not blank -- i.e. line 200 must NOT be the top of the
# viewport with blank rows trailing under it.
last_content_row=$(echo "$QA_SCREEN" | grep -n "line 200" | tail -1 | cut -d: -f1)
total_rows=$(echo "$QA_SCREEN" | wc -l | tr -d ' ')
# The status bar is the final row; the row just above it should be the
# last visible content row, and it should be at (or very near) the bottom
# of the pane, not near the top.
if [[ -n "$last_content_row" && "$last_content_row" -ge $((total_rows - 3)) ]]; then
    qa_pass "line 200 sits at the bottom of the viewport (row $last_content_row of $total_rows), not the top"
else
    qa_fail "line 200 sits at the bottom of the viewport, not the top" \
        "line 200 found at row $last_content_row of $total_rows total rows: $QA_SCREEN"
fi

qa_keys "ctrl-q"
qa_summary
