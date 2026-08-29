#!/usr/bin/env bash
# QA-REG-075: Tree state shows pills in status bar
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-075: Tree status pills"

proj_dir=$(mktemp -d /tmp/zepto_qa_reg075_XXXXXX)
echo "c" > "$proj_dir/test.txt"
echo "d" > "$proj_dir/other.txt"
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start test.txt

qa_keys "ctrl-b"
sleep 0.5

# Status bar should show tree-relevant info
qa_assert_expect "Commands|Open|⌃" "status bar pills visible in tree mode"

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
