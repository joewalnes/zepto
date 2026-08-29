#!/usr/bin/env bash
# QA-CLI-012: CLI flag overrides env var (--tree beats ZEPTO_TREE=0)
# NOTE: hangon sessions do NOT inherit the client env — inject via `env`
# wrapper inside the session command.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-012: Flag overrides env var"

proj_dir=$(mktemp -d /tmp/zepto_qa_cli012_XXXXXX)
echo "content" > "$proj_dir/marker_cli012.txt"

# ZEPTO_TREE=0 hides the tree, but the --tree flag must win
hangon start process --name "$QA_SESSION" -- \
    env ZEPTO_TREE=0 \
    "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" --no-system-clipboard --tree "$proj_dir"
sleep "$QA_RENDER_WAIT"

if qa_wait_screen "marker_cli012"; then
    qa_pass "--tree flag overrides ZEPTO_TREE=0 (tree visible)"
else
    qa_fail "--tree flag overrides ZEPTO_TREE=0" "tree entry not visible"
fi

qa_keys "ctrl-q"
rm -rf "$proj_dir"
qa_summary
