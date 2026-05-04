#!/usr/bin/env bash
# QA-GUT-019: Minimap uses full editor height
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-GUT-019: Minimap uses full editor height (visual)"

content=""
for i in $(seq 1 200); do
    content+="def function_$i(x): return x * $i + $((i % 7))"$'\n'
done
file=$(qa_tmpfile_nl "gut019.py" "$content")
qa_start "$file"
sleep 0.5

shot="$QA_TMPDIR/minimap_height.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a very long code file (200 lines) in a terminal text editor with a minimap on the right side. Focus on the MINIMAP HEIGHT. Verify ALL of these: (1) The minimap column on the right extends from the top of the editing area all the way down to near the bottom (above the status bar). (2) The minimap does NOT stop short or leave a large empty gap at the bottom — it uses the full available vertical space. (3) The minimap content spans the full height of the column, showing a compressed representation of many lines. (4) There is a viewport indicator (highlighted region) within the minimap showing the currently visible portion of the file. (5) The minimap is clearly a narrow column on the far right of the editor." \
    "Minimap extends full height of editor area"

qa_keys "ctrl-q"

qa_summary
