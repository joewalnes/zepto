#!/usr/bin/env bash
# QA-SEC-003: Symlink traversal bounded
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-003: Symlink traversal bounded"

# Create a project dir with a symlink escaping to /etc
project_dir=$(mktemp -d /tmp/zepto_qa_sec003_XXXXXX)
mkdir -p "$project_dir/subdir"
printf 'real file\n' > "$project_dir/subdir/real.txt"
ln -s /etc "$project_dir/escape_link" 2>/dev/null || true

qa_start --tree "$project_dir/subdir/real.txt"
sleep 1

# Tree should show the project but escape_link should be bounded
qa_assert_expect "real.txt" "real file visible in tree"

# The tree should not expose /etc contents as navigable
qa_wait_screen 'real|subdir' || true
if echo "$QA_SCREEN" | grep -q "passwd"; then
    qa_fail "symlink traversal bounded" "saw /etc/passwd in tree"
else
    qa_pass "symlink traversal bounded (no /etc contents visible)"
fi

qa_keys "ctrl-q"
rm -rf "$project_dir"
qa_summary
