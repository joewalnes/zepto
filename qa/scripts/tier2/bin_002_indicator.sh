#!/usr/bin/env bash
# QA-BIN-002: Binary file shows placeholder indicator (not raw bytes)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-BIN-002: Binary file placeholder indicator (visual)"

# Create a binary file with various non-printable bytes
binfile="$QA_TMPDIR/bin002.dat"
printf '\x00\x01\x02\x03\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' > "$binfile"
# Append more random binary data
dd if=/dev/urandom bs=256 count=1 >> "$binfile" 2>/dev/null

qa_start "$binfile"

shot="$QA_TMPDIR/bin_indicator.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a terminal text editor that has opened a BINARY FILE. Verify ALL of these: (1) The editor does NOT display raw binary garbage/mojibake — there should not be screens full of random characters, control characters, or corrupted text. (2) Instead, there is a clear PLACEHOLDER or INDICATOR message telling the user this is a binary file. (3) The indicator might say 'Binary file', 'Cannot display binary content', show a file icon, or similar user-friendly message. (4) The display is clean and intentional — it looks like a designed placeholder, not a rendering error. (5) The status bar at the bottom is still visible and functional." \
    "Binary file shows clean placeholder, not raw bytes"

qa_keys "ctrl-q"

qa_summary
