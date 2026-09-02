#!/usr/bin/env bash
# QA-REG-230: Cursor stays within the document's valid line range after
# undoing a multi-line paste (and through move/redo afterwards).
#
# bugs.md "Cursor can end up outside valid line numbers after paste -> undo".
# Editor::Commands::cmd_undo/cmd_redo called $doc->undo()/$doc->redo() and
# then left the view's cursor exactly where it was. Undoing a multi-line
# paste shrinks the document, so the cursor was left on a line that no
# longer existed.
#
# Symptoms observed on the unfixed binary:
#   - the status bar reported a line number past the end of the document
#   - the next typed character did NOT go where the cursor was drawn:
#     line_col_to_offset() saturates at the last line, so the character
#     silently landed on the last real line instead of the phantom one
#   - the redrawn line was visually mangled ("Xgamm" instead of "Xgamma")
#
# IMPORTANT -- why the paste happens at the END of the document:
# the cursor only ends up out of range if the paste leaves it BELOW the
# document's original last line. An earlier draft of this script pasted at
# the top, which left the cursor on line 3 of a 3-line document after undo:
# in range by coincidence, so that draft passed against the unfixed binary
# and proved nothing. Pasting at the end is what actually reaches the bug.
#
# The broad permutation sweep lives in tests/undo_redo_cursor_bounds.t; the
# command-path unit tests live in tests/editor.t ("Cursor stays in bounds
# across undo/redo").
#
# The pasted block is produced by copying inside the editor (Ctrl+C) rather
# than by seeding the OS clipboard from the shell -- pbcopy/xclip differ per
# platform and this suite must run on Linux and macOS alike.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-230: cursor stays in bounds after undoing a multi-line paste"

# The status bar's line:col indicator is hidden while a transient message
# ("Pasted", "Undo", ...) is showing, and qa_cursor_pos then reads an empty
# string. Dismiss the message first, retrying until the indicator appears.
read_cursor() {
    local attempt
    for attempt in 1 2 3 4; do
        qa_keys "escape" 0.5
        qa_cursor_pos
        [[ -n "$QA_CURSOR_LINE" ]] && return 0
    done
    return 1
}

file=$(qa_tmpfile_nl "reg230_undo_bounds.txt" "alpha
beta
gamma")
qa_start "$file"
qa_assert_expect "alpha" "file opened"
qa_assert_cursor_at "1:1" "cursor starts at line 1"

# --- Copy all three lines, so the clipboard holds a multi-line block ------
qa_keys "shift-down" 0.05
qa_keys "shift-down" 0.05
qa_keys "shift-end" 0.05
qa_keys "ctrl-c" 0.3

# --- Move to the very END of the document, then paste --------------------
# This grows the document from 3 lines to 5 and leaves the cursor on line 5,
# i.e. two lines below the document's original end.
qa_keys "ctrl-g"
qa_send "3" 0.2
qa_keys "enter" 0.3
qa_keys "end" 0.2
qa_keys "ctrl-v" 0.5
qa_assert_expect "Pasted" "paste happened"

read_cursor
if [[ "$QA_CURSOR_LINE" == "5" ]]; then
    qa_pass "after pasting at end of document the cursor is on line 5 (document has 5 lines)"
else
    qa_fail "paste did not leave the cursor where this test needs it" \
            "Expected line 5, got '$QA_CURSOR_LINE' -- the rest of this test would not reach the bug"
fi

# --- Undo: the document shrinks back to 3 lines --------------------------
qa_keys "ctrl-z" 0.5
qa_assert_not_screen "gammaalpha" "undo removed the pasted block"

# THE REGRESSION ASSERTION. On the unfixed binary the status bar still
# reported line 5 here, on a document that now has only 3 lines.
read_cursor
if [[ -z "$QA_CURSOR_LINE" ]]; then
    qa_fail "could not read cursor line from the status bar after undo"
elif [[ "$QA_CURSOR_LINE" -ge 1 && "$QA_CURSOR_LINE" -le 3 ]]; then
    qa_pass "after undo, cursor line $QA_CURSOR_LINE is within the 3-line document"
else
    qa_fail "cursor outside valid line numbers after undo" \
            "Document has 3 lines, status bar reports line $QA_CURSOR_LINE"
fi
claimed_line="$QA_CURSOR_LINE"

# --- Typing must land on the line the cursor claims to be on -------------
# This is the corruption: with a stale out-of-range cursor the character was
# inserted on the last real line while the status bar pointed somewhere else.
qa_send "X" 0.4
qa_keys "ctrl-s" 0.6

saved_lines=$(grep -c '' "$file")
if [[ "$saved_lines" -eq 3 ]]; then
    qa_pass "saved file still has 3 lines (paste stayed undone)"
else
    qa_fail "saved file has $saved_lines lines, expected 3"
fi

if [[ -n "$claimed_line" ]] && [[ "$claimed_line" -ge 1 ]] \
   && [[ "$claimed_line" -le "$saved_lines" ]] \
   && sed -n "${claimed_line}p" "$file" | grep -q 'X'; then
    qa_pass "typed character landed on line $claimed_line, the line the cursor reported"
else
    qa_fail "typed character did not land on the line the cursor reported" \
            "Cursor claimed line '$claimed_line'; file line '$claimed_line' is '$(sed -n "${claimed_line}p" "$file" 2>/dev/null)'"
fi
qa_assert_file_not_contains "$file" "gammaalpha" "pasted block did not reappear in the saved file"

# --- Undo -> move -> redo, the shape the user originally reported --------
qa_keys "ctrl-z" 0.4     # undo the typed X
qa_keys "ctrl-z" 0.4     # undo further
qa_keys "down" 0.2
qa_keys "ctrl-y" 0.4     # redo

read_cursor
cursor_after="$QA_CURSOR_LINE"

# Count the document's real lines by saving and counting the file, rather
# than scraping the rendered screen (the gutter merges with the text when
# the cursor sits on a line, which makes screen-scraped counts unreliable).
qa_keys "ctrl-s" 0.6
final_lines=$(grep -c '' "$file")

if [[ -z "$cursor_after" ]]; then
    qa_fail "could not read cursor line after undo/move/redo"
elif [[ "$cursor_after" -ge 1 && "$cursor_after" -le "$final_lines" ]]; then
    qa_pass "after undo/move/redo, cursor line $cursor_after is within the $final_lines-line document"
else
    qa_fail "cursor outside valid line numbers after undo/move/redo" \
            "Cursor on line $cursor_after, document has $final_lines lines"
fi

qa_keys "ctrl-q"
qa_summary
