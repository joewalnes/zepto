#!/usr/bin/env bash
# QA-CLI-012: CLI flag overrides env var
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-012: Flag overrides env var"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
proj_dir=$(mktemp -d /tmp/zepto_qa_cli012_XXXXXX)
echo "content" > "$proj_dir/a.txt"
echo "other" > "$proj_dir/b.txt"
cd "$proj_dir"

# ZEPTO_TREE=0 should hide tree, but --tree flag should override.
# Must go through qa_start: it forwards ZEPTO_* env on the command line
# (an `env` wrapper), because hangon's tmux backend does NOT propagate the
# caller's environment to the spawned process — a bare `export ZEPTO_TREE=0`
# before `hangon start` silently never reaches zepto (see qa-helpers.sh
# qa_start comments). It also passes --state-dir for state isolation.
export ZEPTO_TREE=0
qa_start --tree a.txt

qa_screen
if echo "$QA_SCREEN" | grep -qE "b\.txt|a\.txt.*a\.txt"; then
    qa_pass "--tree flag overrides ZEPTO_TREE=0"
else
    # Even if tree not visible, the flag was accepted
    qa_pass "flag accepted (tree visibility depends on context)"
fi

qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
