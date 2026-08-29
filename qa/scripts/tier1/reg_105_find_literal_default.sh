#!/usr/bin/env bash
# QA-REG-105: Find bar defaults to literal search, not regex
# Bug: regex mode defaulted to ON, so typing "foo.bar" matched "fooXbar" on
# first use — unexpected for most users (VS Code/Sublime default literal).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-105: Find defaults to literal"

file=$(qa_tmpfile_nl "reg105.txt" "fooXbar
foo.bar
fooYbar")
qa_start "$file"

# Search for "foo.bar" — literal mode must match ONLY the literal line
qa_keys "ctrl-f"
qa_send 'foo.bar' 0.4
qa_assert_expect '1 of 1' "literal search: foo.bar matches exactly 1 line (not 3 via regex dot)"

# Toggling regex ON must then match all three lines
qa_keys "ctrl-r" 0.4
qa_assert_expect '(1|2|3) of 3' "regex toggle ON: dot matches all 3 lines"

qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
