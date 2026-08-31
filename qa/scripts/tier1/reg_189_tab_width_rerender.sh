#!/usr/bin/env bash
# QA-REG-189: The "Tab Width" preference actually changes how EXISTING
# tab characters render/wrap, not just how new indentation is inserted.
#
# Bug: Renderer.pm hardcoded `TAB_WIDTH => 4`, and all three
# tab-expansion functions (_expand_tabs, _char_to_visual_col,
# visual_to_char_col) used that constant unconditionally -- never the
# user's actual tab_width preference. WrapMap.pm stored
# $self->{tab_width} but never read it either. Net effect: changing "Tab
# Width" in the palette had zero visible effect on a file's existing
# literal \t characters -- they kept rendering/wrapping at 4 columns
# regardless of the preference. See bugs.md P1 "Tab Width preference has
# no effect on rendering existing tab characters".
#
# Fix: tab-expansion helpers now accept an optional width (defaulting to
# a package-level effective width that render() syncs from
# $prefs->tab_width() every render pass, mirroring how Zepto::Chars is
# synced from prefs), and WrapMap explicitly passes its own stored
# tab_width through. Editor.pm's WrapMap-rebuild condition now also
# triggers on a tab_width preference change, not just a viewport-width
# change. See tests/renderer.t for the exhaustive helper-level proof;
# this script is the live/interactive confirmation via a real rendered
# screen.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-189: Tab Width preference re-renders existing tabs, live"

# A distinctive marker right after a single leading tab. Its on-screen
# column tells us exactly how wide that tab rendered.
file=$(qa_tmpfile_nl "reg189.txt" "$(printf 'line1\n\tMARKERTAB\nline3')")
qa_start "$file"

# Returns the 0-indexed byte column of "MARKERTAB" on the current screen
# (empty if not found). Guards every step with `|| true` since this
# script runs under `set -euo pipefail` (qa-helpers.sh) -- a grep/cut
# pipeline that legitimately finds nothing must not abort the whole
# script, it must surface as a qa_fail below.
marker_col() {
    qa_screen
    local line col
    line=$(echo "$QA_SCREEN" | grep -m1 'MARKERTAB' || true)
    col=$(echo "$line" | grep -bo 'MARKERTAB' 2>/dev/null | head -1 | cut -d: -f1 || true)
    echo "$col"
}

set_tab_width() {
    local width="$1"
    qa_keys "ctrl-space"
    qa_send "Tab Width"
    qa_assert_expect "Tab Width" "command palette shows Tab Width (discoverable without docs)"
    qa_keys "enter"
    sleep 0.2
    qa_keys "ctrl-a"
    qa_send "$width"
    qa_keys "enter"
    sleep 0.3
}

set_tab_width 2
col_2=$(marker_col)

set_tab_width 8
col_8=$(marker_col)

if [[ -n "$col_2" && -n "$col_8" ]]; then
    delta=$(( col_8 - col_2 ))
    # Going from tab-width 2 to 8 must push a single-leading-tab marker
    # right by exactly 6 columns. Under the old hardcoded-TAB_WIDTH=4
    # code, both settings would render identically (delta=0) since the
    # preference had no effect at all -- this assertion fails against
    # that code and passes only when the width is genuinely threaded
    # through.
    if [[ "$delta" -eq 6 ]]; then
        qa_pass "MARKERTAB shifted right by exactly 6 columns going from tab-width 2 to 8 (col $col_2 -> $col_8)"
    else
        qa_fail "MARKERTAB shifts by exactly 6 columns (8-2) between tab widths" \
            "got delta=$delta (col_2=$col_2 col_8=$col_8) -- tab width preference may not be affecting existing tabs"
    fi
else
    qa_fail "MARKERTAB is visible on screen at both tab widths" "col_2='$col_2' col_8='$col_8'"
fi

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
