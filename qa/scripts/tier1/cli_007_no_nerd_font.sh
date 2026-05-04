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

# Verify no nerd font file icons (common ones: , , , )
# These are multi-byte UTF-8 sequences in the Private Use Area
if echo "$QA_SCREEN" | grep -qP '[\xEE\x80-\xEF\xA3]' 2>/dev/null; then
    qa_fail "no nerd font icons present" "Found PUA characters"
else
    qa_pass "no nerd font icons present"
fi

qa_keys "ctrl-q"
qa_summary
