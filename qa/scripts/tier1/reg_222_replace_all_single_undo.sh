#!/usr/bin/env bash
# QA-REG-222 / QA-REG-223: Replace All produces exactly ONE undo entry
# regardless of match count
#
# bugs.md "Replace All undo granularity inconsistency + Document::replace()
# undo-group bypass". Two related, compounding root causes:
#
#   1. (QA-REG-223) Zepto::Document::replace() built its compound undo
#      action and pushed it straight onto undo_stack unconditionally,
#      completely bypassing the `_undo_group` check that insert()/delete()
#      both go through via _push_undo(). Any caller that wrapped a
#      replace() call in begin_undo_group()/end_undo_group() got the wrong
#      undo granularity: the replace leaked out as its own standalone
#      undo entry instead of joining the group. Latent until this fix
#      (no caller used to combine replace() with an undo group) --
#      exercised directly by tests/document.t's "replace() inside
#      begin/end_undo_group joins the group like insert/delete" subtest.
#   2. (QA-REG-222) Editor.pm's Replace All had two code paths with
#      inconsistent undo granularity: for >100 matches, _replace_all()
#      did one whole-document $doc->replace() call (1 undo entry); for
#      <=100 matches, _replace_all_sync() looped $doc->replace() once per
#      match with no undo group (N undo entries -- pressing Undo once
#      only reverted the LAST match, not all of them). Fixed by wrapping
#      _replace_all_sync()'s loop in begin_undo_group()/end_undo_group(),
#      which only works correctly now that (1) above is fixed.
#
# This script exercises the real, user-visible symptom of both bugs
# together: Replace All with a handful of matches (<=100, the previously
# broken sync path), then a single Ctrl+Z, and asserts ALL matches revert
# at once -- not just the last one. It also spot-checks the >100 fast path
# (already correct before this fix) as a regression guard against the
# unification breaking it.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-222/223: Replace All -- single undo entry regardless of match count"

# --- Small match count (<=100): the previously-broken sync path -----------
file=$(qa_tmpfile_nl "reg222_small.txt" "foo bar foo baz foo
qux foo end")
qa_start "$file"
qa_assert_expect "foo bar foo baz foo" "file opened"

qa_keys "ctrl-f"
qa_send "foo" 0.3
qa_assert_screen "of 4" "4 matches found for 'foo' (sync path: <=100)"

qa_keys "tab"
qa_send "XXX" 0.3
qa_keys "enter" 1.0
qa_assert_expect "Replaced 4 occurrences" "Replace All ran on 4 matches"
qa_assert_screen "XXX bar XXX baz XXX" "document shows all replacements"
qa_assert_screen "qux XXX end" "document shows the replacement on line 2 too"

qa_keys "escape" 0.5
qa_keys "ctrl-z" 0.3
qa_assert_screen "foo bar foo baz foo" \
    "a SINGLE Ctrl+Z fully reverts ALL 4 replacements at once (line 1)"
qa_assert_screen "qux foo end" \
    "a SINGLE Ctrl+Z fully reverts ALL 4 replacements at once (line 2)"
qa_assert_not_screen "XXX" "no leftover XXX anywhere after one undo"

# Redo should restore all 4 at once too, from that same single group entry.
qa_keys "ctrl-y" 0.3
qa_assert_screen "XXX bar XXX baz XXX" "a SINGLE Redo restores ALL 4 replacements at once"
qa_assert_screen "qux XXX end" "redo restored line 2's replacement too"

qa_keys "ctrl-q"
qa_stop

# --- Large match count (>100): fast path regression guard -----------------
# Must still be exactly one undo entry after unifying the two paths onto
# the same undo-group mechanism.
big_content=$(perl -e 'print join("\n", map { "needle line $_" } 1..150)')
file2=$(qa_tmpfile_nl "reg222_big.txt" "$big_content")
qa_start "$file2"
qa_assert_expect "needle line 1" "large file opened"

qa_keys "ctrl-f"
qa_send "needle" 0.3
qa_assert_screen "of 150" "150 matches found (fast path: >100)"

qa_keys "tab"
qa_send "TARGET" 0.3
qa_keys "enter" 1.5
qa_assert_expect "Replaced 150 occurrences" "Replace All ran on 150 matches (fast path)"
qa_assert_screen "TARGET line 1" "document shows replacements (fast path)"

qa_keys "escape" 0.5
qa_keys "ctrl-z" 0.5
qa_assert_screen "needle line 1" \
    "a SINGLE Ctrl+Z fully reverts the entire 150-match fast-path Replace All"
qa_assert_not_screen "TARGET" "no leftover TARGET anywhere after one undo (fast path)"

qa_keys "ctrl-q"
qa_summary
