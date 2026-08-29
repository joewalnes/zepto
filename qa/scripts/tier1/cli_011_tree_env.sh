#!/usr/bin/env bash
# QA-CLI-011: ZEPTO_TREE=0 env var hides tree
# NOTE: hangon sessions do NOT inherit the client env — inject via `env`
# wrapper. Opening a DIRECTORY normally shows the tree, so that's the
# non-tautological probe (a single-file open hides the tree anyway).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-011: ZEPTO_TREE=0 env var"

proj_dir=$(mktemp -d /tmp/zepto_qa_cli011_XXXXXX)
echo "content" > "$proj_dir/marker_cli011.txt"

# Baseline: opening a directory WITHOUT the env var shows the tree
hangon start process --name "$QA_SESSION" -- \
    "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard "$proj_dir"
sleep "$QA_RENDER_WAIT"
if qa_wait_screen "marker_cli011"; then
    qa_pass "baseline: opening a directory shows the tree"
else
    qa_fail "baseline: opening a directory shows the tree"
fi
qa_keys "ctrl-q" 0.3
qa_stop

# With ZEPTO_TREE=0 the tree must be hidden
hangon start process --name "$QA_SESSION" -- \
    env ZEPTO_TREE=0 \
    "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard "$proj_dir"
sleep "$QA_RENDER_WAIT"
qa_screen
if echo "$QA_SCREEN" | grep -q "marker_cli011"; then
    qa_fail "tree hidden with ZEPTO_TREE=0" "tree entry still visible"
else
    qa_pass "tree hidden with ZEPTO_TREE=0"
fi

qa_keys "ctrl-q"
rm -rf "$proj_dir"
qa_summary
