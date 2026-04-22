#!/usr/bin/env bash
# QA-CLI-005: --version prints version and exits
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-005: --version flag"

# Run --version directly (no hangon needed)
set +e
output=$("$QA_ZEPTO" --version 2>&1)
code=$?
set -e

qa_assert_exit 0 "$code" "--version exits with code 0"

if [[ -n "$output" ]]; then
    qa_pass "--version produces output: $output"
else
    qa_fail "--version produces no output"
fi

# Also test -v alias
set +e
output2=$("$QA_ZEPTO" -v 2>&1)
code2=$?
set -e

qa_assert_exit 0 "$code2" "-v exits with code 0"

if [[ "$output" == "$output2" ]]; then
    qa_pass "-v produces same output as --version"
else
    qa_fail "-v output differs from --version" "got: $output2"
fi

qa_summary
