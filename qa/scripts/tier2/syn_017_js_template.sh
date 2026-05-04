#!/usr/bin/env bash
# QA-SYN-017: JS template literal with ${expr} highlighted
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-017: JS template literal highlighting (visual)"

file=$(qa_tmpfile_nl "syn017.js" 'const name = "Alice";
const age = 30;
const items = ["apple", "banana"];

// Simple template literal
const greeting = `Hello, ${name}!`;

// Expression in template
const info = `Next year: ${age + 1} years old`;

// Method call in template
const upper = `Name: ${name.toUpperCase()}`;

// Multi-line template
const html = `
  <div class="card">
    <h1>${name}</h1>
    <p>Age: ${age}</p>
  </div>
`;

// Regular string for comparison
const plain = "This is a normal string";

console.log(greeting);')
qa_start "$file"

shot="$QA_TMPDIR/js_template.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a JavaScript file in a terminal text editor with syntax highlighting. Verify: (1) Template literals (strings in backticks) are highlighted as strings. (2) The \${expressions} inside template literals are visually distinct from the surrounding string text — shown in a different color or style. (3) Regular double-quoted strings are also highlighted. (4) At least 3 distinct colors are visible across keywords, strings, and comments." \
    "JS template literal interpolation expressions highlighted"

qa_keys "ctrl-q"

qa_summary
