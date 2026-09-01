#!/usr/bin/env bash
# QA-TREE-013: Tree filter via / typing
#
# bugs.md P1 "File-tree flat-filter search (FileTree::start_filter/
# filter_active) is fully built and rendered but has zero UI trigger" —
# this script used to qa_skip unconditionally (it typed a query and, if
# nothing filtered, called qa_skip instead of qa_fail — a tautological
# soft-pass that could never catch the bug it claimed to cover, per
# CLAUDE.md "Don't write tautological tests"). Now that '/' actually
# triggers filter mode (Editor.pm::handle_tree_event), this asserts the
# real behavior with qa_fail on mismatch, and also locks in that plain
# typing WITHOUT '/' does NOT filter (the design this bug fix settled on).
# See also QA-REG-216 in qa/40_regression_bugs.txt.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-TREE-013: Tree filter via / trigger"

# Like qa_assert_not_screen, but restricted to the tree PANE (everything
# left of the first "│" divider on each row) — the top tab bar can hold
# an already-open tab whose name happens to contain the pattern (e.g. the
# file that was open before filtering started), which would otherwise
# false-positive a "this file is hidden by the filter" check.
qa_assert_not_tree_pane() {
    local pattern="$1"
    local desc="$2"
    qa_screen
    local tree_pane
    tree_pane="$(echo "$QA_SCREEN" | awk -F'│' '{print $1}')"
    if echo "$tree_pane" | grep -qE "$pattern"; then
        qa_fail "$desc" "Pattern unexpectedly found in tree pane: $pattern"
    else
        qa_pass "$desc"
    fi
}

qa_project
dir="$QA_PROJECT_DIR"
echo "c1" > "$dir/alpha.txt"
echo "c2" > "$dir/beta.txt"
echo "c3" > "$dir/gamma.txt"

qa_start alpha.txt
qa_keys "ctrl-b" 0.3

# --- Sanity: plain typing (no '/' trigger) must NOT filter -----------------
qa_send "bet" 0.3
qa_assert_screen "alpha" "alpha still listed after plain typing with no '/' trigger"
qa_assert_screen "gamma" "gamma still listed after plain typing with no '/' trigger"
qa_assert_screen "/ filter" "hint row still advertises the '/' trigger (filter mode was not entered)"

# --- Activate filter mode with '/' and type a query -------------------------
qa_send "/" 0.2
qa_assert_screen "Esc clear" "hint row swaps to 'Esc clear' once filter mode is active"

qa_send "bet" 0.3
qa_assert_expect "beta" "filter shows the matching file 'beta'"
qa_assert_not_tree_pane "alpha\.txt" "non-matching 'alpha.txt' is hidden from the tree pane by the flat filter view"
qa_assert_not_tree_pane "gamma\.txt" "non-matching 'gamma.txt' is hidden from the tree pane by the flat filter view"

# --- Backspace edits the query and un-filters as it empties -----------------
qa_keys "backspace" 0.2
qa_keys "backspace" 0.2
qa_keys "backspace" 0.2
qa_assert_screen "alpha" "alpha reappears once the query is backspaced back to empty"
qa_assert_screen "gamma" "gamma reappears once the query is backspaced back to empty"

# --- Escape (empty query): exits filter mode, tree stays focused -----------
qa_keys "escape" 0.2
qa_assert_expect "/ filter" "first Escape exits filter mode (hint row reverts to '/ filter')"

# Confirm tree is still focused (not just filter-cleared) by checking the
# ⌃B back pill — unique to the FILE_TREE-context status bar, unlike the
# always-present ⌃␣ Commands pill which also appears in DOCUMENT context.
qa_assert_screen "back" "tree-context status bar still visible — tree remains focused after first Escape"

# --- Escape again: unfocuses the tree back to the editor --------------------
qa_keys "escape" 0.2
qa_send "Z" 0.2
qa_assert_expect "Zc1" "typed 'Z' landed in the editor (tree unfocused after second Escape), prepended to alpha.txt's 'c1' content"

qa_keys "ctrl-z" 0.2   # undo the 'Z' insertion — leave no edits behind
qa_keys "ctrl-q" 0.3
qa_screen
if echo "$QA_SCREEN" | grep -qi "unsaved\|discard\|save"; then
    qa_send "n" 0.2
fi

qa_summary
