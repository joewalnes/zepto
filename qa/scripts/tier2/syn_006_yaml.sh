#!/usr/bin/env bash
# QA-SYN-006: YAML syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-006: YAML syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn006.yaml" '# Application configuration
name: zepto-editor
version: "2.1.0"
debug: false
max_connections: 100

# Server settings
server:
  host: localhost
  port: 8080
  ssl: true
  timeout: 30.5

database:
  driver: postgres
  credentials:
    username: "admin"
    password: "secret123"

# Feature flags
features:
  - syntax-highlighting
  - minimap
  - file-tree

tags:
  env: production
  region: us-east-1

empty_value:
nullable: null
multiline: |
  This is a multi-line
  string value')
qa_start "$file"

shot="$QA_TMPDIR/yaml_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a YAML file in a terminal text editor. Verify: (1) At least 3 distinct colors are visible in the code. (2) YAML keys are in a different color from their values. (3) Comments starting with # are in a muted/gray color." \
    "YAML syntax highlighting with multiple colors"

qa_keys "ctrl-q"

qa_summary
