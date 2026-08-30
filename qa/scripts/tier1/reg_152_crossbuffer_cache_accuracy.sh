#!/usr/bin/env bash
# QA-REG-152: CrossBufferWordProvider's per-document caches stay accurate
# across edits in OTHER tabs.
#
# bugs.md P2 "CrossBufferWordProvider rescans every open tab on every
# trigger, not just the changed one" — fixed by giving each open document
# its own word-frequency cache (keyed by that doc's content_version) with
# a cheap merge step, instead of one shared cache rebuilt wholesale from
# every tab on any change. This script is a behavioral (black-box) check
# that the fix didn't just get faster but stayed CORRECT: after editing
# one tab, completions in a different tab still see (a) the new word from
# the edited tab and (b) words from a third, completely untouched tab.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-152: Cross-buffer completion cache stays accurate across edits"

file_a=$(qa_tmpfile_nl "reg152_a.js" "const longUniqueIdentifierAlpha = 1;")
file_b=$(qa_tmpfile_nl "reg152_b.js" "function main() {
}")
file_c=$(qa_tmpfile_nl "reg152_c.js" "let anotherDistinctIdentifierBeta = 2;")
qa_start "$file_a" "$file_b" "$file_c"

# Move to tab B (opened second) and confirm tab A's word completes there —
# proves the initial cross-buffer scan covers all tabs.
qa_keys "alt-." 0.3
qa_assert_expect "reg152_b" "tab B is now active"
qa_keys "down" 0.1
qa_keys "end" 0.1
qa_send " longUniqueIdent" 0.5
qa_assert_expect "longUniqueIdentifierAlpha" \
    "tab A's word completes in tab B before any edits"
qa_keys "escape" 0.2

# Move to tab A and add a NEW word — this bumps tab A's content_version
# and should rebuild only tab A's per-document cache entry.
qa_keys "alt-," 0.3
qa_assert_expect "reg152_a" "tab A is now active"
qa_keys "end" 0.1
qa_send " freshWordFromTabAlpha" 0.5
qa_keys "escape" 0.2

# Back to tab B: the merged completion view must reflect tab A's edit —
# not just still show the OLD word, but the NEW one too. If the fix had
# accidentally dropped or gone stale on other tabs' cache entries during
# a targeted rescan, this would fail.
qa_keys "alt-." 0.3
qa_assert_expect "reg152_b" "tab B is active again"
qa_keys "end" 0.1
qa_send " freshWordFromTab" 0.6
qa_assert_expect "freshWordFromTabAlpha" \
    "tab B sees the word freshly added to tab A (cache correctly rebuilt for the changed doc)"

# Tab C was never touched — its words must still be present in the merged
# view (proves untouched tabs' cache entries were preserved, not lost).
# NOTE: deliberately no "escape" here before continuing to type — see
# bugs.md "Escape immediately followed by a burst keystroke send can drop
# or corrupt the next character(s)" (found while writing this script).
# Continuing to type directly (as a real user would, without dismissing
# the ghost text first) sidesteps that unrelated issue entirely.
qa_send " anotherDistinct" 0.6
qa_assert_expect "anotherDistinctIdentifierBeta" \
    "tab C's word (never edited) still completes correctly in tab B"
qa_keys "escape" 0.2

# tab_c.js on disk must be completely untouched throughout.
qa_assert_file_contains "$file_c" "^let anotherDistinctIdentifierBeta = 2;\$" \
    "tab C's file on disk is unchanged"

# Clean up: quit and discard changes in both dirty tabs (a and b; c was
# never edited). cmd_quit walks all dirty tabs with one prompt each after
# a single ctrl-q — no need to re-press ctrl-q between prompts. The extra
# trailing ctrl-q/n pair is defensive padding (harmless no-op once quit).
qa_keys "ctrl-q" 0.3
qa_send "n" 0.2
qa_send "n" 0.2
qa_keys "ctrl-q" 0.3
qa_send "n" 0.2
qa_summary
