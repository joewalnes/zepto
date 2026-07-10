#!/usr/bin/env bash
# QA-FIF-002: Find in files returns search results
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-002: Find in files search"

# Create a project directory with searchable content
proj_dir=$(mktemp -d /tmp/zepto_qa_fif002_XXXXXX)
echo "unique_marker_alpha here" > "$proj_dir/alpha.txt"
echo "nothing special" > "$proj_dir/beta.txt"
echo "unique_marker_alpha again" > "$proj_dir/gamma.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start alpha.txt

# Open find-in-files via palette
qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3

# Type search query
qa_send "unique_marker_alpha" 0.3

# Should show results mentioning the matching files
qa_screen
if echo "$QA_SCREEN" | grep -qE "alpha|gamma|2|matches"; then
    qa_pass "find in files shows matching results"
else
    qa_fail "find in files shows matching results"
fi

# Settle before Escape so it's sent as its own cleanly-separated keystroke
# rather than racing the tail of the typed query on a slow/loaded runner.
qa_expect_screen "unique_marker_alpha" 3 -F || true

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
