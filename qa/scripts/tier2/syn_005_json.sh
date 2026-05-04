#!/usr/bin/env bash
# QA-SYN-005: JSON syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-005: JSON syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn005.json" '{
    "name": "zepto-editor",
    "version": "1.0.0",
    "description": "A fast terminal editor",
    "main": "index.js",
    "private": true,
    "count": 42,
    "ratio": 3.14,
    "negative": -7,
    "tags": ["editor", "terminal", "fast"],
    "config": {
        "debug": false,
        "maxRetries": 3,
        "timeout": null,
        "nested": {
            "deep": "value",
            "enabled": true
        }
    },
    "empty": {},
    "list": []
}')
qa_start "$file"

shot="$QA_TMPDIR/json_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a JSON file in a terminal text editor with syntax highlighting. Verify ALL of these: (1) JSON keys (property names in quotes like 'name', 'version', 'config') are highlighted in one distinct color. (2) String values like 'zepto-editor', 'A fast terminal editor' are in a color (may be same or different from keys). (3) Numbers like 42, 3.14, -7, 3 are in a distinct color (typically orange). (4) Boolean values 'true' and 'false' are highlighted in a keyword-like color. (5) The 'null' value is highlighted distinctly. (6) Structural characters (braces {}, brackets [], colons, commas) are visible. (7) At least 3 distinct colors are used." \
    "JSON syntax highlighting with keys, strings, numbers, booleans, null"

qa_keys "ctrl-q"

qa_summary
