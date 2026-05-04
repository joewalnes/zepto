#!/usr/bin/env bash
# QA-SYN-008: Rust syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-008: Rust syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn008.rs" 'use std::collections::HashMap;
use std::io::{self, Read};

/// A simple key-value store
#[derive(Debug, Clone)]
struct Store<'\''a> {
    data: HashMap<String, &'\''a str>,
    count: usize,
    active: bool,
}

impl<'\''a> Store<'\''a> {
    fn new() -> Self {
        Store {
            data: HashMap::new(),
            count: 0,
            active: true,
        }
    }

    pub fn insert(&mut self, key: String, val: &'\''a str) -> Option<&'\''a str> {
        self.count += 1;
        self.data.insert(key, val)
    }

    async fn fetch(&self, id: u64) -> Result<String, io::Error> {
        let url = format!("https://api.example.com/{}", id);
        // TODO: implement actual fetch
        Ok(url)
    }
}

fn main() {
    let mut store = Store::new();
    store.insert("hello".to_string(), "world");
    let x: i32 = 42;
    println!("Count: {}, value: {}", store.count, x);
}')
qa_start "$file"

shot="$QA_TMPDIR/rust_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Rust source file in a terminal text editor. Verify: (1) The code has at least 3 distinct colors (not all one color). (2) Keywords like fn, struct, impl, let are in a different color from identifiers. (3) Strings in double quotes have their own color. (4) Comments (// or ///) are in a muted/gray color." \
    "Rust syntax highlighting with multiple colors"

qa_keys "ctrl-q"

qa_summary
