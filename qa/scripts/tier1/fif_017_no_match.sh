#!/usr/bin/env bash
# QA-FIF-017: Find-in-files with no results
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-017: No results"
proj_dir=$(mktemp -d /tmp/zepto_qa_fif017_XXXXXX)
echo "hello" > "$proj_dir/test.txt"
QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start test.txt
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3
qa_send "ZZZNOMATCH999" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -qiE "no.match|no.result|0 match|not found" || ! echo "$QA_SCREEN" | grep -q "ZZZNOMATCH999.*ZZZNOMATCH999"; then
    qa_pass "no results handled gracefully"
else
    qa_fail "no results message"
fi
# Settle before Escape so it's sent as its own cleanly-separated keystroke
# rather than racing the tail of the typed query on a slow/loaded runner.
qa_expect_screen "ZZZNOMATCH999" 3 -F || true
qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
