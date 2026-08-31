#!/usr/bin/env bash
# QA-PRMT-006: Pill buttons clickable in save prompt
#
# Clicks the Cancel pill of the "Save changes to ...?" quit prompt and
# verifies Cancel's actual, specific effect (Editor::Commands.pm
# _prompt_close_dirty_tabs: choice 'c' does nothing — no save, no
# discard, no quit; it just dismisses the prompt and returns control to
# the editor). Real regressions this catches: click coordinates land on
# the wrong pill (mouse routing broken → editor may quit or discard
# instead), or the click doesn't register at all (prompt stays up,
# further keys go to the modal instead of the document).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-PRMT-006: Prompt pill buttons clickable"

file=$(qa_tmpfile_nl "prmt006.txt" "original")
qa_start "$file"

qa_send "dirty edit"

# Trigger save prompt
qa_keys "ctrl-q"
sleep 0.3

qa_assert_expect "Save|Discard|Cancel" "prompt visible"

# Locate the actual on-screen position of the "Cancel" label so the
# click lands on the real pill, not a hardcoded guess. Icon glyphs in
# earlier pills (e.g. the Save pill's icon) are multi-byte UTF-8, and
# this system's awk computes index() in BYTES, not display columns —
# using it here would overshoot the real column by the byte-length of
# every icon before "Cancel" and click past the pill entirely. Use
# Perl's character-aware index() instead so the column matches the
# terminal's actual column count.
#
# Use qa_wait_screen (polls), not a single qa_screen — under parallel
# suite runs a fixed single capture can race a still-in-flight render
# and flake even right after qa_assert_expect confirmed the prompt.
qa_wait_screen "Cancel" || true
cancel_row=$(echo "$QA_SCREEN" | grep -n "Cancel" | tail -1 | cut -d: -f1 || true)
cancel_line_text=$(echo "$QA_SCREEN" | sed -n "${cancel_row}p")
cancel_col=$(printf '%s' "$cancel_line_text" | perl -CSD -ne 'my $i = index($_, "Cancel"); print $i >= 0 ? $i + 1 : 0;')

if [[ -z "$cancel_row" || "$cancel_col" -eq 0 ]]; then
    qa_fail "Cancel pill located on screen" "could not find 'Cancel' text in rendered prompt"
    qa_keys "ctrl-q"
    sleep 0.2
    qa_send "n"
    qa_summary
    exit
fi
qa_pass "Cancel pill located on screen (row $cancel_row, col $cancel_col)"

# Click mid-word on "Cancel" (index() is 1-based, already matches
# terminal x coordinates).
hangon mouse-click "$QA_SESSION" --x "$((cancel_col + 2))" --y "$cancel_row"
sleep 0.3

qa_assert_not_screen "Save changes to" "prompt dismissed after clicking Cancel"

if qa_alive 2>/dev/null; then
    qa_pass "editor still running after Cancel click (did not quit)"
else
    qa_fail "editor still running after Cancel click (did not quit)" "session died"
fi

# Verify by action: Cancel must return control to the document, not
# leave input trapped in a modal. Type a marker and confirm it lands
# in the buffer — this is unfakeable: if the prompt (or a stuck state)
# were still intercepting input, this text would never reach the doc.
qa_send "CANCELMARKER"
qa_assert_screen "CANCELMARKER" "keyboard input reaches the document again after Cancel"

# Clean up: discard the (still-dirty) file and quit for real.
qa_keys "ctrl-q"
sleep 0.3
qa_send "n" 0.2
qa_summary
