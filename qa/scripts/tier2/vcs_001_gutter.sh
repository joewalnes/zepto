#!/usr/bin/env bash
# QA-VCS-001: Git gutter markers appear for changed lines
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-VCS-001: Git gutter markers (visual)"

# This test requires a git repo with a tracked file
# Create a temp git repo
repo="$QA_TMPDIR/repo"
mkdir -p "$repo"
cd "$repo"
git init -q
echo "line 1 original" > test.txt
echo "line 2 original" >> test.txt
echo "line 3 original" >> test.txt
echo "line 4 original" >> test.txt
echo "line 5 original" >> test.txt
git add test.txt
git commit -q -m "initial"

# Modify the file
cat > test.txt <<'CONTENT'
line 1 original
line 2 MODIFIED
line 3 original
new line inserted
line 4 original
line 5 original
CONTENT

cd - >/dev/null

qa_start "$repo/test.txt"
sleep 0.8  # wait for VCS diff computation

shot="$QA_TMPDIR/vcs_gutter.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text file in a terminal editor that is tracked by git. The file has been modified. Look at the LEFT GUTTER (the narrow column to the left of the line numbers). Verify: (1) At least one line has a YELLOW or AMBER colored marker in the gutter (indicating a modified line). (2) At least one line has a GREEN colored marker (indicating a newly added line). (3) Lines that haven't changed have NO colored marker (just blank/empty gutter). (4) The colored markers are small blocks or symbols in the leftmost column of the gutter." \
    "VCS gutter shows colored markers for modified/added lines"

qa_keys "ctrl-q"

qa_summary
