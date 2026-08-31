#!/usr/bin/env bash
# QA-REG-195: VCS::Git::is_tracked() correctly reports tracked/untracked
# status for a filename starting with '-' — see bugs.md P2
# "VCS/Git.pm::is_tracked() has a git argument-injection edge case".
#
# Before the fix, `_git('ls-files', '--error-unmatch', $rel_path)` had no
# `--` separator before the pathspec, so a relative path starting with
# '-' (e.g. "-weird.txt") could be parsed by git as an option instead of
# a path, causing is_tracked() to misreport.
#
# Intentionally non-interactive (no hangon/zepto session), unlike most
# scripts in this directory: `grep -rn is_tracked lib/` confirms this
# method currently has ZERO callers anywhere in the editor's runtime
# code (it's a public VCS::Provider API method exercised only by unit
# tests today) — there is no command, keybinding, or rendered UI element
# that invokes it, so there is nothing for a hangon session to drive or
# observe. This script instead exercises the real library code path
# directly against a real git repository, mirroring the interactive
# scripts' spirit (reproduce the exact bug scenario end-to-end) as
# closely as possible given that constraint. See
# tests/vcs.t "Git is_tracked for filename starting with dash" for the
# equivalent (and primary) unit-level coverage.
#
# The dash-prefixed file is created via Perl's open() with an explicit
# path, never shell globbing/commands, which would otherwise interpret
# a leading '-' as a flag.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-195: is_tracked() handles dash-prefixed filenames"

if ! command -v git &>/dev/null; then
    qa_skip "git not available"
    qa_summary
    exit 0
fi

qa_git_repo
dir="$QA_PROJECT_DIR"

# Tracked dash-prefixed file
perl -e 'open(my $fh, ">", $ARGV[0]) or die $!; print $fh "tracked dash content\n"; close $fh' \
    "$dir/-tracked.txt"
git add -- -tracked.txt
git commit -m "Add dash-prefixed tracked file" --quiet

# Untracked dash-prefixed file
perl -e 'open(my $fh, ">", $ARGV[0]) or die $!; print $fh "untracked dash content\n"; close $fh' \
    "$dir/-untracked.txt"

result=$(perl -I"$_QA_ORIG_DIR/lib" -e '
    use strict; use warnings;
    use Zepto::VCS::Git;
    my $provider = Zepto::VCS::Git->detect($ARGV[0]);
    die "no provider detected\n" unless $provider;
    print "tracked=" . ($provider->is_tracked($ARGV[0]) ? 1 : 0) . "\n";
    print "untracked=" . ($provider->is_tracked($ARGV[1]) ? 1 : 0) . "\n";
' "$dir/-tracked.txt" "$dir/-untracked.txt" 2>&1)

if echo "$result" | grep -q "^tracked=1$"; then
    qa_pass "dash-prefixed tracked file correctly reported as tracked"
else
    qa_fail "dash-prefixed tracked file correctly reported as tracked" "$result"
fi

if echo "$result" | grep -q "^untracked=0$"; then
    qa_pass "dash-prefixed untracked file correctly reported as untracked"
else
    qa_fail "dash-prefixed untracked file correctly reported as untracked" "$result"
fi

qa_summary
