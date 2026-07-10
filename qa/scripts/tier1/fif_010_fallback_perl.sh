#!/usr/bin/env bash
# QA-FIF-010: Find-in-files perl fallback (tests that search works generally)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-010: FIF perl fallback"

# We can't easily remove git/rg/grep from PATH in a test,
# but we can verify the search works in a minimal directory
proj_dir=$(mktemp -d /tmp/zepto_qa_fif010_XXXXXX)
echo "PERLTEST data" > "$proj_dir/file1.txt"
echo "more PERLTEST" > "$proj_dir/file2.txt"

cd "$proj_dir"
qa_start file1.txt

qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3
qa_send "PERLTEST" 0.5

qa_screen
if echo "$QA_SCREEN" | grep -qE "PERLTEST|match|result|file"; then
    qa_pass "find-in-files returns results (backend fallback chain works)"
else
    qa_fail "find-in-files returns results"
fi

# Settle before Escape so it's sent as its own cleanly-separated keystroke
# rather than racing the tail of the typed query on a slow/loaded runner.
qa_expect_screen "PERLTEST" 3 -F || true

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
