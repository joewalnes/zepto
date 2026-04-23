#!/usr/bin/env bash
# QA-VCS-012: Non-git directory has no VCS errors
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-VCS-012: No VCS errors outside git repo"

# Create a file outside any git repo
nogit_dir=$(mktemp -d /tmp/zepto_qa_nogit_XXXXXX)
echo "no git here" > "$nogit_dir/test.txt"

qa_start "$nogit_dir/test.txt"

qa_assert_screen "no git here" "file content displayed"
qa_assert_not_screen "fatal|error|Error|FATAL" "no git errors"

qa_keys "ctrl-q"

rm -rf "$nogit_dir"
qa_summary
