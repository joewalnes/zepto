#!/usr/bin/env bash
# QA-REG-154: File-tree preview failure surfaces an error message
#
# Regression test for the P3 bug "Silent eval swallow in file-tree preview
# open": _tree_preview_current() wrapped document creation in a bare
# eval {} with no `if ($@)` check, so a failed preview (permission error,
# decode failure) produced no message at all — dead silence.
#
# The tree only lists files that pass `-r` at scan time (see
# FileTree::_scan_dir_one_level), so a file that's unreadable from the
# start never appears in the tree to navigate to. The realistic trigger
# is a TOCTOU race: a file is readable when the tree scans, then loses
# read permission before the user arrows onto it and a preview is
# attempted. This script simulates that race.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-154: Tree preview failure shows error message"

proj_dir=$(mktemp -d /tmp/zepto_qa_reg154_XXXXXX)
echo "readable content" > "$proj_dir/aaa_readable.txt"
echo "will be blocked" > "$proj_dir/zzz_blocked.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir"
qa_start aaa_readable.txt

qa_keys "ctrl-b"
sleep 0.5

qa_assert_expect "aaa_readable" "tree shows the readable file"
qa_assert_expect "zzz_blocked" "tree shows the file that will be blocked"

# Preview the target file once while it's still readable, to prove
# normal preview isn't affected by this fix.
qa_keys "down" 0.2
qa_assert_expect "will be blocked" "preview shows content while file is readable"

# Now revoke read permission — simulating a race between the tree scan
# and the preview attempt (permissions changed, filesystem hiccup, etc).
chmod 000 "$proj_dir/zzz_blocked.txt"

# Force a fresh preview attempt: move off the file and back onto it.
qa_keys "up" 0.2
qa_keys "down" 0.2

qa_assert_expect "Preview failed|Permission denied" "error message shown for failed preview"
qa_assert_not_screen "die|Carp|at line [0-9]+\.$" "no Perl stack trace leaked to the screen"

# Editor must still be alive and usable — no crash, no stuck state.
if qa_alive; then
    qa_pass "editor survived preview failure (no crash)"
else
    qa_fail "editor crashed on preview failure"
fi

# Navigating to a different readable file afterward must still preview
# normally — the failed attempt must not leave the tree/tab state stuck.
qa_keys "up" 0.2
qa_assert_expect "readable content" "preview of a different readable file still works after the failure"

# Restore permissions so the OS can clean up the temp dir.
chmod 644 "$proj_dir/zzz_blocked.txt"

qa_keys "escape"
qa_keys "ctrl-q"

cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
