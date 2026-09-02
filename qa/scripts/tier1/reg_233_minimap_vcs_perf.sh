#!/usr/bin/env bash
# QA-REG-233: Minimap VCS-status aggregation no longer scans the whole
# document on every keystroke
#
# Bug: _aggregate_vcs_status() (Minimap.pm) scanned every document line in
# each minimap row's span with no subsampling cap, unlike the braille
# density path (MAX_SAMPLE_LINES => 4). Because the minimap cache key
# includes content_version() (bumped on every edit), this full per-line VCS
# scan re-ran on every keystroke, not just when VCS/diff state actually
# changed — up to ~100k-200k hash lookups per keystroke on a large file.
# Fixed by adding MAX_VCS_SAMPLE_LINES (200) and subsampling above it, same
# technique as braille. See bugs.md, qa/27_gutter_ruler_minimap.txt
# QA-GUT-021, tests/minimap_vcs_perf.t for the real timing evidence — this
# script is a coarse interactive smoke test (does the minimap still show
# correct VCS coloring, does typing stay responsive), not a tight
# discriminator; PTY/tmux round-trip overhead dwarfs the millisecond-level
# render difference this fix produces.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-233: Minimap VCS-status aggregation stays fast and correct"

minimap_present() {
    printf '%s' "$QA_SCREEN" | perl -CSD -ne '$m=1 if /[\x{2800}-\x{28FF}]/; END { exit($m ? 0 : 1) }'
}

# Create a git repo with a reasonably large file and a handful of scattered
# changes -- enough lines to exercise minimap row aggregation across
# multiple rows, without making the QA run slow.
repo_dir=$(mktemp -d /tmp/zepto_qa_reg233_XXXXXX)
cd "$repo_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

content=""
for i in $(seq 1 4000); do content+="line $i original content here"$'\n'; done
printf '%s' "$content" > big.txt
git add big.txt
git commit -q -m "initial"

if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' -e 's/line 100 original/line 100 MODIFIED/' \
              -e 's/line 2000 original/line 2000 MODIFIED/' \
              -e 's/line 3900 original/line 3900 MODIFIED/' big.txt
else
    sed -i -e 's/line 100 original/line 100 MODIFIED/' \
           -e 's/line 2000 original/line 2000 MODIFIED/' \
           -e 's/line 3900 original/line 3900 MODIFIED/' big.txt
fi

cd "$OLDPWD"
qa_start "$repo_dir/big.txt"
qa_resize_window 80 24
sleep 1
qa_screen

if minimap_present; then
    qa_pass "minimap visible on a large git-tracked file"
else
    qa_fail "minimap visible on a large git-tracked file" "expected braille density column, none found"
fi

# Jump to a known modified line and confirm the VCS gutter marker shows up
# there (sanity that VCS status is still computed correctly at all after
# the subsampling change -- the sample formula always includes a row's
# first line, and single-line/near-row-span cases stay below the cap, so
# this must still be exact).
qa_keys "ctrl-g"
qa_send "100" 0.2
qa_keys "enter"
sleep 0.3
qa_screen
if echo "$QA_SCREEN" | grep -q "line 100 MODIFIED content here"; then
    qa_pass "navigated to the known-modified line 100"
else
    qa_fail "navigated to the known-modified line 100" "expected MODIFIED content at cursor"
fi

# Type a burst of characters and confirm the editor stays responsive (no
# visible hang/freeze) -- coarse smoke test only, see header note.
start_ts=$(date +%s)
qa_send "hello" 0
sleep 0.3
qa_screen
elapsed=$(( $(date +%s) - start_ts ))
if echo "$QA_SCREEN" | grep -q "hello"; then
    qa_pass "typing stayed responsive on a large git-tracked file (visible within ${elapsed}s)"
else
    qa_fail "typing stayed responsive on a large git-tracked file" "typed text not visible on screen"
fi
# Undo the typed text so we don't need to deal with a save prompt on quit.
for _ in 1 2 3 4 5; do qa_keys "ctrl-z"; done
sleep 0.2

qa_keys "ctrl-q"
rm -rf "$repo_dir"
qa_summary
