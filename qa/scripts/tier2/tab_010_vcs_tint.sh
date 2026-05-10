#!/usr/bin/env bash
# QA-TAB-010: VCS-changed file has tinted tab name
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-TAB-010: VCS-changed tab tint (visual)"

repo=$(qa_git_repo)
echo "original content" > "$repo/clean.txt"
echo "original content" > "$repo/changed.txt"
cd "$repo" && git add . && git commit -q -m "init" && cd - >/dev/null

# Modify one file
echo "modified content" > "$repo/changed.txt"

qa_start "$repo/clean.txt" "$repo/changed.txt"
sleep 1.5

# Switch to changed tab
qa_keys "alt-."
sleep 0.3

shot="$QA_TMPDIR/tab010.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with 2 tabs. One file is unchanged in git, the other is modified. Look at the TAB BAR. Verify: (1) Two tabs are visible with filenames. (2) The tabs have slightly different coloring — the modified file's tab name may have an amber/yellow tint compared to the clean file's tab." \
    "VCS-modified file tab has different color tint"

qa_keys "ctrl-q"

qa_summary
