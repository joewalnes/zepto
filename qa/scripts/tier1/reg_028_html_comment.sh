#!/usr/bin/env bash
# QA-REG-028: HTML context-aware toggle comment
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-028: HTML toggle comment uses <!-- -->"

file=$(qa_tmpfile_nl "reg028.html" "<div>hello</div>
<p>world</p>")
qa_start "$file"

# Toggle comment on line 1 (Ctrl+/ = 0x1f)
qa_raw $'\x1f'

qa_assert_screen "<!--" "HTML comment opening tag added"

# Uncomment
qa_raw $'\x1f'
qa_assert_screen "<div>" "HTML comment removed, div restored"

qa_keys "ctrl-q"
qa_summary
