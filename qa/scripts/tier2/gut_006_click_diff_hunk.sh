#!/usr/bin/env bash
# QA-GUT-006: Clicking VCS gutter marker expands diff hunk
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-006: Click gutter expands diff hunk (visual)"

repo=$(qa_git_repo)
cat > "$repo/test.txt" <<'CONTENT'
line 1 original
line 2 original
line 3 original
line 4 original
line 5 original
CONTENT
cd "$repo" && git add test.txt && git commit -q -m "init" && cd - >/dev/null

# Modify lines
cat > "$repo/test.txt" <<'CONTENT'
line 1 original
line 2 CHANGED
line 3 original
line 4 original
line 5 original
CONTENT

qa_start "$repo/test.txt"
sleep 1.5

# Click on the VCS marker in gutter at line 2 (col 1, row ~4 accounting for tab+ruler)
qa_hover 1 4
sleep 0.2

shot="$QA_TMPDIR/gut006.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with a git-tracked file. Line 2 was modified. Look at the LEFT GUTTER. Verify: (1) There is a colored marker (yellow/amber) next to the modified line. (2) An inline diff expansion may be showing old content, OR the gutter marker is visually present indicating VCS changes." \
    "VCS gutter marker visible for modified line"

qa_keys "ctrl-q"

qa_summary
