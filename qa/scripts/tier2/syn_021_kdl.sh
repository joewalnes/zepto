#!/usr/bin/env bash
# QA-SYN-021: KDL file gets syntax highlighting
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-021: KDL highlighting (visual)"

file=$(qa_tmpfile_nl "syn021.kdl" 'package {
    name "my-project"
    version "1.0.0"
    // Comment here
    authors "Alice" "Bob"
}

dependencies {
    serde "1.0"
    tokio version="1.0" features=["full"]
}')
qa_start "$file"

shot="$QA_TMPDIR/syn021.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a KDL configuration file. Verify: (1) At least 2 distinct colors are visible. (2) The comment line (// Comment here) is in a muted/gray color different from other text." \
    "KDL file with syntax coloring"

qa_keys "ctrl-q"
qa_summary
