#!/usr/bin/env bash
# QA-SYN-004: CSS syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-004: CSS syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn004.css" '/* Main stylesheet for the application */
:root {
    --primary: #3498db;
    --bg-dark: rgb(26, 26, 46);
    --font-size: 16px;
}

body {
    background-color: var(--bg-dark);
    font-family: "Helvetica Neue", sans-serif;
    margin: 0;
    padding: 20px;
}

.container > .header {
    display: flex;
    justify-content: center;
    border: 1px solid #ccc;
    border-radius: 8px;
}

#main-content p:first-child {
    color: var(--primary);
    font-size: 1.5rem;
    line-height: 1.6;
}

@media (max-width: 768px) {
    .container { flex-direction: column; }
}')
qa_start "$file"

shot="$QA_TMPDIR/css_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a CSS file in a terminal text editor with syntax highlighting. Verify: (1) The code is NOT all one color — there are at least 3 distinct colors visible. (2) Comments (/* */) appear in a muted/gray color distinct from code. (3) Strings in quotes have their own color. (4) Some keywords or values are highlighted differently from plain text." \
    "CSS syntax highlighting with multiple colors"

qa_keys "ctrl-q"

qa_summary
