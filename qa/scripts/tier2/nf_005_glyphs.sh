#!/usr/bin/env bash
# QA-NF-005: With nerd font ON, tree shows file-type icons
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-NF-005: Nerd font file-type icons in tree (visual)"

# Create a directory structure with various file types
mkdir -p "$QA_TMPDIR/nfdir/src"
echo "print('hello')" > "$QA_TMPDIR/nfdir/src/main.py"
echo "console.log('hi')" > "$QA_TMPDIR/nfdir/src/app.js"
echo "<html></html>" > "$QA_TMPDIR/nfdir/src/index.html"
echo "body {}" > "$QA_TMPDIR/nfdir/src/style.css"
echo "# readme" > "$QA_TMPDIR/nfdir/README.md"
echo '{"a":1}' > "$QA_TMPDIR/nfdir/data.json"

qa_start --tree "$QA_TMPDIR/nfdir/src/main.py"
sleep 0.5

shot="$QA_TMPDIR/nf_glyphs.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a terminal text editor with a FILE TREE panel on the left. Nerd font icons should be enabled. Verify: (1) File entries in the tree have small ICONS next to their names — these are special glyphs (not plain ASCII characters like dashes or brackets). (2) At least 2 different icon shapes are visible for different file types (e.g., Python, JS, HTML files may have distinct icons). (3) The tree panel shows filenames with these icon glyphs to their left." \
    "Nerd font icons visible next to files in tree"

qa_keys "ctrl-q"

qa_summary
