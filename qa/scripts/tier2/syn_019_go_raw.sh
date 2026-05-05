#!/usr/bin/env bash
# QA-SYN-019: Go backtick raw string highlighted
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-019: Go raw string (visual)"

file=$(qa_tmpfile_nl "syn019.go" 'package main

import "fmt"

func main() {
    normal := "hello"
    raw := `raw "string" with newlines
    and multiple lines`
    fmt.Println(normal, raw)
}')
qa_start "$file"

shot="$QA_TMPDIR/syn019.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Go source file. Verify: (1) At least 3 distinct colors visible. (2) String content (in double quotes or backticks) has a distinct color from keywords. (3) The keyword 'func', 'package', 'import' are highlighted." \
    "Go file with syntax highlighting"

qa_keys "ctrl-q"
qa_summary
