#!/usr/bin/env bash
# QA-PERF-022: File tree with many collapsed dirs + many changed files
# renders within budget (not a hang, not gross sluggishness).
#
# Exercises FileTree.pm's VCS-status-to-unloaded-directory propagation
# (_propagate_dir_status / _build_vcs_dir_index) with a repo shaped to
# stress it: many collapsed top-level directories (D) and many changed
# files scattered across them (S). This used to be an O(D*S) full-hash
# rescan per unloaded directory (bugs.md's 2026-09-01 "FileTree scans
# entire VCS status hash per unloaded directory" fix) -- this script is
# the coarse hang-detection leg (see qa/lib/qa-perf-helpers.sh header);
# the precise before/after timing proof (real Time::HiRes numbers, old
# vs. new algorithm at multiple D/S scales) lives in the unit-level
# regression test tests/filetree_vcs_perf.t, cross-referenced as
# QA-REG-229 in qa/40_regression_bugs.txt.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-PERF-022: File tree VCS status with many dirs/changes"

qa_git_repo; dir="$QA_PROJECT_DIR"

D=50   # collapsed top-level directories
FILES_PER_DIR=6

for i in $(seq 1 "$D"); do
    mkdir -p "dir_$i"
    for f in $(seq 1 "$FILES_PER_DIR"); do
        echo "line $f in dir_$i" > "dir_$i/file_$f.txt"
    done
done
echo "# marker readme" > README.md
git add -A
git commit -q -m "initial"

# Change roughly half the files across every directory (~150 changed
# files spread across all 50 dirs) -- worst case for the old per-directory
# full-hash scan, since every directory's lookup had to walk the whole
# changed-files list.
for i in $(seq 1 "$D"); do
    echo "modified" >> "dir_$i/file_1.txt"
    echo "modified" >> "dir_$i/file_2.txt"
    echo "new untracked file" > "dir_$i/untracked_$i.txt"
done

qa_start README.md

# File tree starts hidden — a single ctrl-b shows it (and focuses it),
# which is also what triggers the initial VCS status scan/propagation
# across every collapsed directory.
t0=$(qa_perf_now)
qa_keys "ctrl-b" 0

# Any "dir_NN" entry appearing proves the tree actually rendered its
# directory listing -- including having run VCS status propagation across
# all 50 collapsed dirs and ~150 changed files -- rather than hanging
# partway through. (Not anchored to "dir_1" specifically: the initial
# scroll position lands wherever the active tab's file sorts among the
# tree entries, not necessarily at the top.)
qa_assert_perf "file tree with 50 dirs / ~150 changed files renders" 4 "dir_[0-9]" 20 "$t0"

qa_assert_not_screen "fatal|error|Error|FATAL" "no VCS/tree errors"

qa_keys "ctrl-q"
qa_summary
