#!/usr/bin/env bash
# QA-REG-177: Minimap auto-hides below MINIMAP_MIN_COLS (60 cols)
#
# Bug (confirmed via direct screenshot inspection at 40x15): the minimap
# only ever checked whether there was DYNAMIC room left after gutter/tree
# width (MIN_TEXT_WIDTH), never a hard "is this width even worth it"
# floor. At 40 cols that dynamic check still passed (plenty of text width
# remained), so the minimap kept rendering — eating a meaningful fraction
# of an already-scarce 40 columns for a zoomed-out view that's barely
# legible at that scale, crowding out document content and status bar
# pills that matter more. Renderer.pm::get_minimap_width and the inline
# duplicate in render() now also require $cols >= MINIMAP_MIN_COLS (60).
# See bugs.md 2026-08-30, qa/27_gutter_ruler_minimap.txt QA-GUT-020.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-177: Minimap auto-hides below MINIMAP_MIN_COLS"

# Portable braille-block detector (U+2800-U+28FF) -- avoids relying on
# grep's Unicode support, which differs between BSD grep (macOS, no -P)
# and GNU grep (Linux). Perl is a guaranteed dependency (CLAUDE.md).
minimap_present() {
    printf '%s' "$QA_SCREEN" | perl -CSD -ne '$m=1 if /[\x{2800}-\x{28FF}]/; END { exit($m ? 0 : 1) }'
}

content=""
for i in $(seq 1 60); do content+="line number $i with some extra content to pad width"$'\n'; done
file=$(qa_tmpfile_nl "reg177.txt" "$content")
qa_start "$file"

# Ensure minimap preference is ON (default, but don't assume).
qa_keys "ctrl-space"
qa_send "minimap" 0.2
qa_wait_screen '\[(on|off)\]' || true
state=$(echo "$QA_SCREEN" | grep -oE '\[(on|off)\]' | head -1)
qa_keys "escape" 0.2
qa_keys "escape" 0.2
if [[ "$state" == "[off]" ]]; then
    qa_keys "alt-m"
    sleep 0.3
fi

qa_resize_window 80 24
sleep 0.3
qa_screen
if minimap_present; then
    qa_pass "minimap visible at 80 cols (wide, long document)"
else
    qa_fail "minimap visible at 80 cols" "expected braille density column, none found"
fi

qa_resize_window 60 20
sleep 0.3
qa_screen
if minimap_present; then
    qa_pass "minimap still visible at 60 cols (== MINIMAP_MIN_COLS threshold)"
else
    qa_fail "minimap still visible at 60 cols" "threshold is inclusive, should still show"
fi

qa_resize_window 59 20
sleep 0.3
qa_screen
if minimap_present; then
    qa_fail "minimap hidden at 59 cols (one below threshold)" "braille chars still present"
else
    qa_pass "minimap hidden at 59 cols (one below threshold)"
fi

qa_resize_window 40 15
sleep 0.3
qa_screen
if minimap_present; then
    qa_fail "minimap hidden at 40 cols" "braille chars still present -- original bug"
else
    qa_pass "minimap hidden at 40 cols"
fi
# No layout glitch: tab bar and status bar (Commands pill) still present.
qa_assert_screen "reg177" "tab bar still shows filename at 40 cols"
qa_assert_screen "Commands" "status bar still shows Commands pill at 40 cols"

# Manual toggle (⌥M) must keep working normally ABOVE the threshold --
# this fix must not turn it into a no-op or a new forced-off state.
qa_resize_window 80 24
sleep 0.3
qa_screen
before=$(minimap_present && echo yes || echo no)
qa_keys "alt-m"
sleep 0.3
qa_screen
after=$(minimap_present && echo yes || echo no)
if [[ "$before" != "$after" ]]; then
    qa_pass "manual ⌥M toggle still works above the threshold (80 cols): $before -> $after"
else
    qa_fail "manual ⌥M toggle still works above the threshold" "state unchanged ($before)"
fi
# Toggle back to restore original state
qa_keys "alt-m"

qa_keys "ctrl-q"
qa_summary
