#!/usr/bin/env bash
# QA-GUT-013: Minimap VCS column shows colored marks
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-013: Minimap VCS column (visual)"

repo=$(qa_git_repo)
content=""
for i in $(seq 1 80); do
    content+="line $i original"$'\n'
done
echo -n "$content" > "$repo/big.txt"
cd "$repo" && git add big.txt && git commit -q -m "init" && cd - >/dev/null

# Modify several lines spread through the file
qa_sed_i 's/line 10 original/line 10 MODIFIED/' "$repo/big.txt"
qa_sed_i 's/line 20 original/line 20 MODIFIED/' "$repo/big.txt"
qa_sed_i 's/line 40 original/line 40 MODIFIED/' "$repo/big.txt"
qa_sed_i 's/line 60 original/line 60 MODIFIED/' "$repo/big.txt"

qa_start "$repo/big.txt"
sleep 1.5

shot="$QA_TMPDIR/gut013.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a text editor with a git-tracked file and a MINIMAP on the right. Verify: (1) The minimap is visible on the right side. (2) The left gutter shows colored VCS markers (yellow/green) next to modified lines. (3) Small colored marks may also be visible in or near the minimap column corresponding to changed lines." \
    "Minimap shows VCS change markers"

qa_keys "ctrl-q"

qa_summary
