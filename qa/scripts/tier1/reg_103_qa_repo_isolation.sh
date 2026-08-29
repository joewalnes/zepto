#!/usr/bin/env bash
# QA-REG-103: qa_project/qa_git_repo never touch a pre-existing git repo
# Bug: qa_project cd'd inside a command substitution — `dir=$(qa_git_repo)`
# ran in a subshell, the cd was lost, and the caller's git init/add/commit
# executed in the REAL repo (committed the whole working tree as
# "init"/"initial" with author Test, and rewrote local git config).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-103: QA helpers repo isolation"

helpers="$(cd "$(dirname "$0")/../../lib" && pwd)/qa-helpers.sh"

# Build a scratch "victim" repo standing in for a real user checkout
victim=$(mktemp -d /tmp/zepto_qa_victim_XXXXXX)
(
    cd "$victim"
    git init -q
    git config user.email "victim@example.com"
    git config user.name "Victim"
    echo "precious" > real.txt
    git add real.txt
    git commit -q -m "victim work"
)
before=$(git -C "$victim" rev-parse HEAD)

# Case 1: correct usage, invoked with cwd inside the victim repo.
# Must cd into the temp project dir; a follow-up git commit (the standard
# script pattern) must land in the temp repo, not the victim.
set +e
(
    cd "$victim"
    QA_ZEPTO="$QA_ZEPTO" bash -c '
        source "$1"
        qa_git_repo
        dir="$QA_PROJECT_DIR"
        [ "$PWD" = "$dir" ] || exit 9
        echo x > test.txt
        git add test.txt
        git commit -q -m "initial"
        # The commit must exist here in the temp repo
        git rev-parse HEAD >/dev/null || exit 8
    ' _ "$helpers"
)
case1=$?
set -e
if [[ $case1 -eq 0 ]]; then
    qa_pass "qa_git_repo cds into temp project and commits land there"
else
    qa_fail "qa_git_repo direct usage broken" "child exited $case1"
fi

# Case 2: the legacy dangerous pattern `dir=$(qa_git_repo)` must abort
# loudly instead of silently running git against the caller's repo.
set +e
(
    cd "$victim"
    QA_ZEPTO="$QA_ZEPTO" bash -c '
        source "$1"
        dir=$(qa_git_repo)
        echo x > test.txt
        git add test.txt
        git commit -q -m "initial"
    ' _ "$helpers"
) 2>/dev/null
case2=$?
set -e
if [[ $case2 -ne 0 ]]; then
    qa_pass "command-substitution misuse aborts instead of polluting"
else
    qa_fail "command-substitution misuse did not abort"
fi

# The victim repo must be byte-for-byte untouched in every case
after=$(git -C "$victim" rev-parse HEAD)
dirty=$(git -C "$victim" status --porcelain)
cfg=$(git -C "$victim" config user.email)
if [[ "$before" == "$after" && -z "$dirty" && "$cfg" == "victim@example.com" ]]; then
    qa_pass "victim repo untouched (HEAD, worktree, config)"
else
    qa_fail "victim repo was modified" "HEAD $before -> $after; dirty: $dirty; email: $cfg"
fi

rm -rf "$victim"
qa_summary
