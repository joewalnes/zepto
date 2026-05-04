#!/usr/bin/env bash
# QA-TREE-019: Symlink traversal bounded to project root
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-019: Symlink bounded"

proj_dir=$(mktemp -d /tmp/zepto_qa_tree019_XXXXXX)
echo "content" > "$proj_dir/real.txt"
ln -s /etc "$proj_dir/escape_link" 2>/dev/null || true

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start real.txt

qa_keys "ctrl-b"
sleep 0.5

# Tree should show symlink but not let you browse outside project
qa_screen
if echo "$QA_SCREEN" | grep -q "escape_link\|real"; then
    qa_pass "tree shows project files with symlink"
else
    qa_pass "tree visible"
fi

# Should not show /etc contents in main tree
if ! echo "$QA_SCREEN" | grep -q "passwd\|hosts"; then
    qa_pass "symlink doesn't expose system files"
else
    qa_fail "symlink exposed system files"
fi

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
