#!/usr/bin/env bash
# QA-CLI-007: --no-nerd-font disables nerd font icons
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-CLI-007: --no-nerd-font shows ASCII fallbacks"

mkdir -p "$QA_TMPDIR/nfdir"
echo "content" > "$QA_TMPDIR/nfdir/test.txt"

qa_start --no-nerd-font --tree "$QA_TMPDIR/nfdir/test.txt"

# With --no-nerd-font, tree should use ASCII indicators
# Nerd font icons like , , etc. should NOT appear
# Instead we expect plain text or ASCII-only characters
qa_screen
# Check editor is alive and showing content
if echo "$QA_SCREEN" | grep -qE "test\.txt|content"; then
    qa_pass "editor opened with --no-nerd-font"
else
    qa_fail "editor opened with --no-nerd-font"
fi

# Verify no nerd font / PUA glyphs remain (file icons, tab pill corners,
# etc). Nerd Font icons live in the Unicode Private Use Area (U+E000-U+F8FF).
# NOTE: the old check here was a raw *byte*-range regex ([\xEE\x80-\xEF\xA3])
# which matched almost any multi-byte UTF-8 lead/continuation byte —
# including totally unrelated, always-present Unicode symbols this editor
# intentionally uses even in ASCII-fallback mode (•, ×, ←, →, ⌃, ⌥, ␣). That
# made the check both a false-positive minefield AND blind to anything
# outside its (wrong) byte range. Decode the screen as UTF-8 and check
# actual code points instead: true PUA range, plus the specific U+25E2/
# U+25E3 tab-bar corner triangles (QA-REG-103) which aren't technically PUA
# but are exactly the kind of decorative nerd-font-style glyph
# --no-nerd-font is supposed to eliminate.
qa_screen
if echo "$QA_SCREEN" | perl -CS -0777 -ne 'exit(/[\x{E000}-\x{F8FF}\x{25E2}\x{25E3}]/ ? 1 : 0)'; then
    qa_pass "no nerd font / PUA glyphs present"
else
    qa_fail "no nerd font / PUA glyphs present" "Found PUA or tab-triangle characters"
fi

qa_keys "ctrl-q"
qa_summary
