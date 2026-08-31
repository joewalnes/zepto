#!/usr/bin/env bash
# QA-GUT-002: Minimap click navigates to position
#
# Uses the exact geometry Editor::_handle_minimap_click() derives from a
# mouse event (Editor.pm ~1820-1836, ~2318-2347):
#   text_row    = y - 3                      (tab bar + ruler = 2 rows)
#   text_height = terminal_rows - RESERVED_ROWS (RESERVED_ROWS = 3)
#   ratio       = text_row / (text_height - 1)
#   target_line = round(ratio * (total_lines - 1))
# A click on row y=3 (the very first content row) always maps to
# text_row=0 -> ratio=0 -> target_line=0 (doc line 1). A click on the
# last content row (y = terminal_rows - 1) always maps to ratio=1 ->
# target_line = total_lines-1 (the last line). These are exact,
# deterministic, not fuzzy — real regressions (wrong scaling, off-by-one,
# dead click handler) will land the cursor somewhere else and fail.
#
# The bottom-row click in particular can't be explained away by a
# fallthrough to ordinary text-area clicking: with only ~20-30 lines
# visible starting from line 1, an ordinary (non-minimap) click at that
# row would land on whatever's visible near the viewport's bottom, never
# on the document's actual last line — so landing exactly on the last
# line is only possible if the minimap intercepted and handled the click.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-GUT-002: Minimap click"

total_lines=150
content=""
for i in $(seq 1 $total_lines); do content+="line $i content here"$'\n'; done
file=$(qa_tmpfile_nl "gut002.txt" "$content")
qa_start "$file"

# qa_tmpfile_nl appends its own trailing newline on top of $content's
# own trailing newline, leaving one extra blank line in the document —
# so the document actually has total_lines+1 lines, not total_lines.
doc_total_lines=$((total_lines + 1))

# Check current minimap state via the command palette badge.
qa_keys "ctrl-space"
qa_send "minimap" 0.3
qa_screen
initial_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Ensure minimap is ON.
if [[ "$initial_state" != "[on]" ]]; then
    qa_keys "alt-m"
    sleep 0.3
fi

qa_keys "ctrl-space"
qa_send "minimap" 0.3
qa_screen
now_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1 || true)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ "$now_state" == "[on]" ]]; then
    qa_pass "minimap enabled"
else
    qa_fail "minimap enabled" "expected [on] badge, got '$now_state'"
fi

# Determine actual terminal geometry — never hardcode rows/cols, they
# vary across environments.
qa_screen
term_rows=$(echo "$QA_SCREEN" | wc -l | tr -d ' ')
term_cols=$(echo "$QA_SCREEN" | head -1 | awk '{print length}')

# Click the very top of the minimap column (rightmost edge, first
# content row) -> must land on line 1.
hangon mouse-click "$QA_SESSION" --x "$term_cols" --y 3
sleep 0.3
qa_assert_cursor_at "1" "click at top of minimap navigates to line 1"

# Click the very bottom of the minimap column (rightmost edge, last
# content row, just above the status bar) -> must land on the last line.
bottom_row=$((term_rows - 1))
hangon mouse-click "$QA_SESSION" --x "$term_cols" --y "$bottom_row"
sleep 0.3
qa_assert_cursor_at "$doc_total_lines" "click at bottom of minimap navigates to last line ($doc_total_lines)"

# Restore original state
if [[ "$initial_state" != "[on]" ]]; then
    qa_keys "alt-m"
fi

qa_keys "ctrl-q"
qa_summary
