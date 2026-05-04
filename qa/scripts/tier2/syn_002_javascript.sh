#!/usr/bin/env bash
# QA-SYN-002: JavaScript syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-002: JavaScript syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn002.js" "// Utility module for data processing
import { readFile } from 'fs/promises';

const MAX_ITEMS = 100;
let counter = 0;

/* Multi-line comment
   explaining the function */
function processData(items) {
    if (items.length > MAX_ITEMS) {
        throw new Error('Too many items');
    }
    return items.filter(x => x !== null);
}

const greet = (name) => {
    const msg = \`Hello, \${name}! Count: \${counter++}\`;
    console.log(msg);
    return { name, count: 42, active: true };
};

async function fetchAll(urls) {
    const results = await Promise.all(
        urls.map(url => fetch(url))
    );
    return results;
}

export default processData;")
qa_start "$file"

shot="$QA_TMPDIR/js_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a JavaScript file in a terminal text editor with syntax highlighting. Verify ALL of these: (1) Keywords like 'import', 'from', 'const', 'let', 'function', 'if', 'return', 'throw', 'new', 'async', 'await', 'export', 'default' are highlighted in a distinct color (typically purple/blue). (2) Strings like 'fs/promises', 'Too many items' are in a different color (typically green or yellow). (3) Template literal with backticks is highlighted as a string. (4) The single-line comment '// Utility module' and multi-line comment /* ... */ are in a muted/gray color. (5) Numbers like 100, 0, 42 are in their own color (typically orange). (6) The arrow function '=>' is visible. (7) At least 4 distinct colors are used across the code." \
    "JavaScript syntax highlighting with distinct token colors"

qa_keys "ctrl-q"

qa_summary
