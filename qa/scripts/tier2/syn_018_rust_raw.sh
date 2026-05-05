#!/usr/bin/env bash
# QA-SYN-018: Rust raw string r#"..."# highlighted
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-018: Rust raw string (visual)"

file=$(qa_tmpfile_nl "syn018.rs" 'fn main() {
    let normal = "hello world";
    let raw = r#"raw "string" here"#;
    let multi = r##"another "raw" one"##;
    println!("{} {} {}", normal, raw, multi);
}')
qa_start "$file"

shot="$QA_TMPDIR/syn018.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Rust source file. Verify: (1) At least 3 distinct colors are visible. (2) String literals (in double quotes) have a distinct color. (3) The keyword 'fn' and 'let' are in a different color from identifiers." \
    "Rust file with syntax highlighting"

qa_keys "ctrl-q"
qa_summary
