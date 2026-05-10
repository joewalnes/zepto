#!/usr/bin/env bash
# QA-TAB-011: Long tab name truncated with ellipsis
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-TAB-011: Long filename tab truncation (visual)"

longname="supercalifragilisticexpialidocious_filename.txt"
file=$(qa_tmpfile_nl "$longname" "content inside long-named file")
short=$(qa_tmpfile_nl "short.txt" "short file")
qa_start "$file" "$short"

shot="$QA_TMPDIR/tab011.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with 2 tabs at the top. One file has a very long name. Verify: (1) The long filename is TRUNCATED in the tab — it does NOT show the full name. (2) An ellipsis character (…) or similar truncation indicator is visible in the long tab name. (3) Both tabs fit within the tab bar." \
    "Long filename truncated with ellipsis in tab"

qa_keys "ctrl-q"

qa_summary
