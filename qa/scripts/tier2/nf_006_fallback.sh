#!/usr/bin/env bash
# QA-NF-006: With --no-nerd-font, tree shows ASCII fallback characters
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-NF-006: No-nerd-font ASCII fallback in tree (visual)"

# Create a directory structure with various file types
mkdir -p "$QA_TMPDIR/nfdir/src"
echo "print('hello')" > "$QA_TMPDIR/nfdir/src/main.py"
echo "console.log('hi')" > "$QA_TMPDIR/nfdir/src/app.js"
echo "<html></html>" > "$QA_TMPDIR/nfdir/src/index.html"
echo "# readme" > "$QA_TMPDIR/nfdir/README.md"

qa_start --no-nerd-font --tree "$QA_TMPDIR/nfdir/src/main.py"
sleep 0.5

shot="$QA_TMPDIR/nf_fallback.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a terminal text editor with a FILE TREE panel on the left, running in no-nerd-font mode. Verify: (1) File entries in the tree use plain ASCII characters or simple Unicode symbols as indicators — NOT special nerd font icon glyphs. (2) The tree is readable and shows filenames clearly. (3) Folder and file entries are distinguishable using text-based indicators (such as brackets, slashes, arrows, or plain text)." \
    "Tree shows ASCII fallback characters without nerd font icons"

qa_keys "ctrl-q"

qa_summary
