#!/usr/bin/env bash
# QA-REG-135: Markdown emphasis delimiters dimmed, not full punctuation weight
#
# bugs.md P3 "Dim Markdown formatting delimiters" — **, *, _, ~~, ==
# delimiters now tokenize as TOKEN_FORMATTING_DELIM (themed faint) instead
# of TOKEN_PUNCTUATION. Color assertions live in the tier-2 visual script
# (md_012_dim_delimiters.sh) and the deterministic unit test
# (tests/syntax_rendering.t). This tier-1 script is a fast, non-visual
# regression guard for the part `hangon screen` CAN verify without color:
# that no characters were hidden/concealed by the change, and that the
# feature doesn't break editing of a markdown file containing every
# delimiter kind.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-135: Markdown emphasis delimiters still fully visible (no concealment)"

file=$(qa_tmpfile_nl "reg135.md" 'This is **bold text** and this is *italic text*.
This is ***bold and italic*** combined.
This is ~~strikethrough text~~ here.
This is ==highlighted text== here.
Also __bold__ and _italic_ with underscores.')
qa_start "$file"

# Every delimiter character and every piece of delimited content must still
# be on screen verbatim -- dimming is a color-only change (no concealment).
qa_assert_screen '\*\*bold text\*\*' "** bold delimiters + content still rendered"
qa_assert_screen '\*italic text\*' "* italic delimiters + content still rendered"
qa_assert_screen '\*\*\*bold and italic\*\*\*' "*** bold-italic delimiters + content still rendered"
qa_assert_screen '~~strikethrough text~~' "~~ strikethrough delimiters + content still rendered"
qa_assert_screen '==highlighted text==' "== highlight delimiters + content still rendered"
qa_assert_screen '__bold__' "__ bold delimiters + content still rendered"
qa_assert_screen '_italic_' "_ italic delimiters + content still rendered"

# Sanity: editor is still alive and responsive after rendering every
# delimiter kind (no crash / no infinite loop from the tokenizer change).
qa_keys "ctrl-g"
qa_send "3" 0.2
qa_keys "enter"
qa_assert_cursor_at "3:1" "goto-line still works after markdown emphasis rendering"

qa_keys "ctrl-q"
qa_summary
