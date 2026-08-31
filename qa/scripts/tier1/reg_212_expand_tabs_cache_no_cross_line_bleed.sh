#!/usr/bin/env bash
# QA-REG-212: Renderer's tab-expansion memo cache does not bleed a stale
# result between two DIFFERENT lines that happen to share identical
# content, and correctly recomputes for the edited line without disturbing
# the shared cache entry the unedited line still relies on.
#
# Bug: bugs.md "Scorecard audit round 3" P2 "Renderer.pm's _expand_tabs()
# has no cache -- same missed pattern the Highlighter token cache (round 2)
# just fixed". _expand_tabs() was recomputed from scratch for every visible
# line on every render(), even though most visible lines are unchanged
# frame-to-frame.
#
# Fix: a content-keyed memo cache (tab_width => text => [expanded,
# char_to_visual]), mirroring WrapMap.pm's _wrap_cache / Highlighter.pm's
# _token_cache "pure function of the inputs" design. Because the cache is
# keyed by CONTENT (not line number), two different document lines with
# byte-identical text legitimately share one cache entry -- this script
# specifically exercises that scenario, which is unique to this fix's
# design (a naive per-line-number cache would not have this risk at all,
# but also wouldn't help when scrolling/typing shifts which line number
# holds which content). The risk this guards against: editing one of the
# two lines corrupting the shared entry so the OTHER, untouched line
# renders wrong, or the edited line failing to pick up its own new content.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-212: expand_tabs cache -- no stale bleed between lines sharing content"

# Lines 2 and 4 start out byte-identical ("\tSHARED_TAB_TEXT") -- they will
# hit the SAME cache entry. Lines 1/3/5 are filler so line numbers are
# unambiguous in the gutter. Uses a .js extension (not .txt) so word wrap
# defaults OFF (see Preferences::should_default_wrap -- .txt/.md/prose
# extensions default to wrap-on, which changes Home's "smart home" cycling
# semantics and would just add noise to this test's navigation, unrelated
# to the fix under test here).
file=$(qa_tmpfile_nl "reg212.js" "$(printf 'line one\n\tSHARED_TAB_TEXT\nline three\n\tSHARED_TAB_TEXT\nline five')")
qa_start "$file"

# Returns the 0-indexed screen column of the Nth (1 or 2) occurrence of
# SHARED_TAB_TEXT. Guarded with `|| true` since this runs under
# `set -euo pipefail` and a legitimate "not found" must surface as qa_fail,
# not abort the script.
marker_col() {
    local occurrence="$1"
    qa_screen
    local line
    line=$(echo "$QA_SCREEN" | grep -n 'SHARED_TAB_TEXT' | sed -n "${occurrence}p" || true)
    echo "$line" | grep -bo 'SHARED_TAB_TEXT' 2>/dev/null | head -1 | cut -d: -f1 || true
}

col_line2_before=$(marker_col 1)
col_line4_before=$(marker_col 2)

if [[ -z "$col_line2_before" || -z "$col_line4_before" ]]; then
    qa_fail "both SHARED_TAB_TEXT markers visible before edit" "line2='$col_line2_before' line4='$col_line4_before'"
else
    qa_pass "both SHARED_TAB_TEXT markers visible before edit"
fi
if [[ "$col_line2_before" == "$col_line4_before" ]]; then
    qa_pass "identical-content lines 2 and 4 render the tab-marker at the same column (col $col_line2_before) -- same cache entry, as expected"
else
    qa_fail "identical-content lines render at the same column" "line2=$col_line2_before line4=$col_line4_before"
fi

# Edit ONLY line 2: add a second leading tab, pushing its marker further
# right. Line 4 keeps the original single-tab content untouched. Ctrl+G
# already lands the cursor at column 1 (true line start), so no extra
# Home press is needed.
qa_keys "ctrl-g" 0.2
qa_send "2" 0.2
qa_keys "enter" 0.3
qa_assert_cursor_at "2:1" "cursor jumped to line 2, column 1 (true start, before the leading tab)"
qa_keys "tab" 0.3

col_line2_after=$(marker_col 1)
col_line4_after=$(marker_col 2)

if [[ -n "$col_line2_after" && "$col_line2_after" -gt "$col_line2_before" ]]; then
    qa_pass "edited line 2 (extra leading tab) recomputes to a further-right column ($col_line2_before -> $col_line2_after)"
else
    qa_fail "edited line 2 shifts right after adding a tab" "before=$col_line2_before after=$col_line2_after"
fi
if [[ "$col_line4_after" == "$col_line4_before" ]]; then
    qa_pass "unedited line 4 (still original content) is UNCHANGED at column $col_line4_after -- shared cache entry was not corrupted by line 2's edit"
else
    qa_fail "unedited line 4 stays at its original column" "before=$col_line4_before after=$col_line4_after -- cache bleed between lines sharing content"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
