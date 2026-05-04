#!/usr/bin/env bash
# QA-SYN-013: TOML syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-013: TOML syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn013.toml" '# Project configuration
[package]
name = "zepto-editor"
version = "1.0.0"
edition = "2021"
authors = ["Alice <alice@example.com>", "Bob"]

[dependencies]
serde = { version = "1.0", features = ["derive"] }
tokio = "1.28"

[dev-dependencies]
pretty_assertions = "1.3"

# Server settings
[server]
host = "0.0.0.0"
port = 8080
debug = false
max_connections = 100
timeout = 30.5

[server.tls]
enabled = true
cert_path = "/etc/ssl/cert.pem"

[[routes]]
path = "/api/v1"
method = "GET"
handler = "api_handler"

[[routes]]
path = "/health"
method = "GET"
handler = "health_check"

[logging]
level = "info"
timestamps = true')
qa_start "$file"

shot="$QA_TMPDIR/toml_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a TOML configuration file in a terminal text editor. Verify: (1) At least 3 distinct colors are visible in the code. (2) Section headers in brackets like [package] are in a different color from values. (3) Strings in quotes have their own color. (4) Comments starting with # are in a muted/gray color." \
    "TOML syntax highlighting with multiple colors"

qa_keys "ctrl-q"

qa_summary
