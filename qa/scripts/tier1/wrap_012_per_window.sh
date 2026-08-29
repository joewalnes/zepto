#!/usr/bin/env bash
# QA-WRAP-012: .md file starts with wrap ON, .py starts with wrap OFF
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-WRAP-012: Per-filetype wrap default"

md_file=$(qa_tmpfile_nl "wrap012.md" "# Markdown file")
py_file=$(qa_tmpfile_nl "wrap012.py" "x = 1")
qa_start "$md_file" "$py_file"

# Check wrap state for .md file via palette. Query the full label ("Word
# Wrap"), not the bare substring "wrap" — that now also fuzzy-matches
# "Search Wrap Around" (QA-PREF-019) and would grab the wrong toggle's
# on/off state.
qa_keys "ctrl-space"
qa_send "Word Wrap" 0.3
qa_screen
md_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

# Switch to .py tab
qa_keys "alt-."
sleep 0.3

# Check wrap state for .py file
qa_keys "ctrl-space"
qa_send "Word Wrap" 0.3
qa_screen
py_state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2

if [[ "$md_state" == "[on]" ]]; then
    qa_pass "markdown file defaults to wrap on"
else
    qa_fail "markdown file defaults to wrap on (got $md_state)"
fi

if [[ "$py_state" == "[off]" ]]; then
    qa_pass "python file defaults to wrap off"
else
    qa_fail "python file defaults to wrap off (got $py_state)"
fi

qa_keys "ctrl-q"
qa_summary
