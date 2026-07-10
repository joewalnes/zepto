#!/usr/bin/env bash
# QA-FIF-011: Large result set doesn't hang
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-FIF-011: Large result set no hang"

proj_dir=$(mktemp -d /tmp/zepto_qa_fif011_XXXXXX)
# Create many files with a common string
for i in $(seq 1 50); do
    echo "return value $i" > "$proj_dir/file_$i.txt"
done

cd "$proj_dir"
qa_start file_1.txt

qa_keys "ctrl-space"
qa_send "find in" 0.3
qa_keys "enter" 0.3
qa_send "return" 0.8

# Editor should remain responsive — check it's alive
if qa_alive 2>/dev/null; then
    qa_pass "editor responsive with many search results"
else
    qa_fail "editor hung with large result set"
fi

# Can still type to refine
qa_send " value 1" 0.5
if qa_alive 2>/dev/null; then
    qa_pass "can refine search query during large result set"
else
    qa_fail "refinement hung editor"
fi

# Settle before Escape so it's sent as its own cleanly-separated keystroke
# rather than racing the tail of the typed query on a slow/loaded runner.
qa_expect_screen "value 1" 3 -F || true

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
