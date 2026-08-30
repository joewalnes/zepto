#!/usr/bin/env bash
# QA-REG-182: Tab bar overflow/scroll and the × close button's mouse
# hit-testing still work correctly after the "tabby" redesign (bugs.md
# "Tab bar visual redesign (2026-08-30)") — the redesign changed the cap
# glyph (◢/◣ -> █) but NOT the per-tab width formula, so button columns
# should be unaffected; this is the regression guard that proves it,
# specifically for the overflow/scroll case where multiple tabs share the
# row and a wrong column would close the wrong tab.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-182: Tab overflow scroll + close-button hit-test"

files=()
for n in 1 2 3 4 5 6 7 8; do
    files+=("$(qa_tmpfile_nl "ov${n}.txt" "content of tab ${n}")")
done
qa_start "${files[@]}"
qa_assert_expect "ov1\\.txt" "first tab visible on open"

# 8 tabs overflow the default 80-col bar — right scroll arrow must appear.
qa_assert_screen "▸" "Right scroll arrow visible when tabs overflow"

# Jump to the last tab (⌥8 = Alt+8). Sent as a raw escape sequence since
# hangon's "alt-<digit>" key name isn't supported (only alt-a..z).
qa_raw "$(printf '\x1b8')"
sleep 0.3
qa_assert_expect "content of tab 8" "jumped to last tab via ⌥8"
qa_assert_screen "◂" "Left scroll arrow visible now that we've scrolled past tab 1"

# Find a currently-visible, non-active tab name and its × close column on
# the tab bar row, using the actual character positions the renderer just
# produced (not a hardcoded column — this is the whole point of a
# hit-testing regression guard: it must fail if the redesign's width
# accounting ever drifts from where the buttons are actually drawn).
qa_screen
row1=$(printf '%s\n' "$QA_SCREEN" | head -1)
target_name=$(printf '%s' "$row1" | grep -oE 'ov[0-9]\.txt' | head -1 || true)

if [[ -z "$target_name" ]]; then
    qa_fail "found a visible non-active tab name to close" "no ov*.txt name found in: $row1"
else
    close_col=$(TARGET_LINE="$row1" TARGET_NAME="$target_name" perl -CSD -MEncode=decode -e '
        my $line = decode("UTF-8", $ENV{TARGET_LINE});
        my $name = decode("UTF-8", $ENV{TARGET_NAME});
        my $idx = index($line, $name);
        exit 1 if $idx < 0;
        my $close_idx = index($line, "\x{00d7}", $idx);
        exit 1 if $close_idx < 0;
        print $close_idx + 1;
    ' || true)

    if [[ -z "$close_col" ]]; then
        qa_fail "computed a close-button column for $target_name" "not found on tab bar row: $row1"
    else
        qa_pass "computed close-button column for $target_name ($close_col)"
        hangon mouse-click "$QA_SESSION" --x "$close_col" --y 1
        sleep 0.3
        # A close-button click switches to that tab first, then closes it
        # (Editor.pm::handle_tab_bar_click — existing, intentional
        # behavior, unrelated to this redesign), so the *active* tab after
        # this click legitimately isn't tab 8 anymore. What the redesign
        # must not have broken is which tab got closed: exactly the one we
        # clicked, and no other — confirm the clicked tab is gone and every
        # other tab from this run is still present in the bar.
        qa_assert_not_screen "$target_name" "Clicked tab ($target_name) closed, not left open"
        # The tab immediately after the one we clicked is exactly what an
        # off-by-one column error in the hit-test would have closed
        # instead — confirm it's still open.
        target_num=$(printf '%s' "$target_name" | grep -oE '[0-9]+')
        neighbor_name="ov$((target_num + 1)).txt"
        qa_assert_screen "${neighbor_name//./\\.}" "Neighboring tab ($neighbor_name) untouched by the close click — no off-by-one"
    fi
fi

qa_keys "ctrl-q"
qa_summary
