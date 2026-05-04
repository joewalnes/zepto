#!/usr/bin/env bash
# QA-SYN-003: HTML syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-003: HTML syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn003.html" '<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Test Page</title>
    <style>
        body { background: #1a1a2e; color: white; }
        .header { font-size: 24px; margin: 10px; }
    </style>
</head>
<body>
    <div class="header" id="main">
        <h1>Hello World</h1>
        <p>Count: <span>42</span></p>
        <!-- This is an HTML comment -->
        <a href="https://example.com">Link</a>
    </div>
    <script>
        const x = document.getElementById("main");
        console.log(x.textContent);
    </script>
</body>
</html>')
qa_start "$file"

shot="$QA_TMPDIR/html_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows an HTML file in a terminal text editor with syntax highlighting. Verify ALL of these: (1) HTML tags like <html>, <head>, <body>, <div>, <h1>, <p>, <script>, <style> are highlighted — the tag names should be in a distinct color. (2) Attribute names like 'lang', 'charset', 'class', 'id', 'href' are in a color different from tag names. (3) Attribute values in quotes like 'en', 'UTF-8', 'header' are highlighted as strings. (4) The HTML comment <!-- ... --> is in a muted/gray color. (5) The embedded CSS block (body { background... }) shows some CSS-specific coloring. (6) The embedded JavaScript block shows some JS-specific coloring. (7) At least 4 distinct colors are visible across the file." \
    "HTML syntax highlighting with tags, attributes, and embedded CSS/JS"

qa_keys "ctrl-q"

qa_summary
