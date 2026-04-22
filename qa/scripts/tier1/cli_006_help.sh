#!/usr/bin/env bash
# QA-CLI-006: --help prints usage and exits
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-006: --help flag"

set +e
output=$("$QA_ZEPTO" --help 2>&1)
rc=$?
set -e

qa_assert_exit 0 "$rc" "--help exits with code 0"

if echo "$output" | grep -q "install\|version\|Usage\|usage"; then
    qa_pass "--help mentions install/version/usage"
else
    qa_fail "--help mentions install/version/usage"
fi

qa_summary
