#!/usr/bin/env bash
# QA-REG-193: ImageConverter.pm uses File::Temp for secure temp file
# creation (unpredictable name, exclusive open) instead of the old
# predictable "$tmpdir/zepto-img-$$-$basename" path — see bugs.md P2
# "ImageConverter.pm uses a predictable temp filename with no exclusive
# creation - symlink-follow risk".
#
# Opens a real (non-PNG) JPEG that requires conversion, on a
# Kitty-graphics-capable terminal, and confirms the full pipeline still
# works end to end: sips/convert successfully produces a PNG at the new
# File::Temp-generated path, and that PNG is transmitted over the Kitty
# graphics protocol. Since a headless hangon/tmux session can't decode
# and visually render Kitty graphics pixels (confirmed empirically: even
# `hangon screenshot` only rasterizes the text grid, not transmitted
# image data — same limitation QA-REG-175 documents for markdown inline
# images), this verifies the transmitted escape sequence and payload
# directly: `hangon readall` returns the raw output stream (unlike
# `hangon screen`, which is the rendered text grid), so we can grep it
# for the Kitty APC image-transmission sequence and base64-decode the
# payload to confirm it's a real PNG.
#
# Requires a Kitty-graphics-capable TERM_PROGRAM for the image display
# path to engage at all (Zepto::Terminal->supports_kitty_graphics()).
# hangon sessions do NOT inherit the client's shell environment (see
# qa_start's own comment in qa-helpers.sh), so TERM_PROGRAM must be set
# on the *invoked command itself* via `env`, not exported before calling
# hangon — this script therefore calls `hangon start` directly instead
# of qa_start, matching QA-REG-175's established pattern.
#
# Requires sips (macOS) or convert (ImageMagick) to be installed — skips
# gracefully if neither is available, matching tests/image_converter.t.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-193: ImageConverter uses File::Temp (secure temp file)"

if ! command -v sips &>/dev/null && ! command -v convert &>/dev/null; then
    qa_skip "sips/convert not available on this system"
    qa_summary
    exit 0
fi

# A real, valid, minimal 16x16 baseline JPEG (same fixture bytes as
# tests/image_converter.t), decoded from base64 so this script doesn't
# depend on any external tool to produce its own fixture.
jpeg_path="$QA_TMPDIR/photo.jpg"
perl -MMIME::Base64 -e '
open(my $fh, ">:raw", $ARGV[0]) or die $!;
local $/;
my $b64 = <STDIN>;
print $fh MIME::Base64::decode_base64($b64);
close $fh;
' "$jpeg_path" <<'B64EOF'
/9j/4AAQSkZJRgABAQAASABIAAD/4QCARXhpZgAATU0AKgAAAAgABAEaAAUAAAABAAAAPgEbAAUA
AAABAAAARgEoAAMAAAABAAIAAIdpAAQAAAABAAAATgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQAD
AAAAAQABAACgAgAEAAAAAQAAABCgAwAEAAAAAQAAABAAAAAA/+0AOFBob3Rvc2hvcCAzLjAAOEJJ
TQQEAAAAAAAAOEJJTQQlAAAAAAAQ1B2M2Y8AsgTpgAmY7PhCfv/AABEIABAAEAMBIgACEQEDEQH/
xAAfAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgv/xAC1EAACAQMDAgQDBQUEBAAAAX0BAgMA
BBEFEiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVG
R0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0
tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+fr/xAAfAQADAQEBAQEB
AQEBAAAAAAAAAQIDBAUGBwgJCgv/xAC1EQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2Fx
EyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZ
WmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TF
xsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2wBDAAICAgICAgMCAgMFAwMDBQYFBQUF
BggGBgYGBggKCAgICAgICgoKCgoKCgoMDAwMDAwODg4ODg8PDw8PDw8PDw//2wBDAQICAgQEBAcE
BAcQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/
3QAEAAH/2gAMAwEAAhEDEQA/AM+iiiv5XP7YP//Z
B64EOF

if [[ ! -s "$jpeg_path" ]]; then
    qa_fail "test JPEG fixture created" "no bytes written to $jpeg_path"
    qa_summary
    exit 1
fi
qa_pass "test JPEG fixture created ($(wc -c < "$jpeg_path" | tr -d ' ') bytes)"

hangon start process --name "$QA_SESSION" -- env TERM_PROGRAM=ghostty "$QA_ZEPTO" \
    --state-dir "$QA_STATE_DIR" --no-system-clipboard "$jpeg_path"
sleep "$QA_RENDER_WAIT"

qa_assert_expect "photo.jpg" "JPEG file tab is open"
qa_assert_expect "Image file" "placeholder text shown for the image buffer"

# Give the render loop a moment to emit the first frame (which triggers
# the Kitty image transmission for image-file tabs).
sleep 0.5

raw_file="$QA_TMPDIR/raw_output.bin"
hangon readall "$QA_SESSION" > "$raw_file" 2>/dev/null

if grep -qa '_Ga=T,f=100,i=99' "$raw_file"; then
    qa_pass "Kitty graphics image-transmission escape sequence was emitted (f=100 PNG format, id=99)"
else
    qa_fail "Kitty graphics image-transmission escape sequence was emitted" \
        "no _Ga=T,f=100,i=99 sequence found in raw output — ensure_png() may have failed silently"
fi

# Extract and decode the base64 payload, confirm it's a real PNG. This
# directly proves ensure_png() (now File::Temp-based) produced a valid
# converted file that got read back and transmitted correctly.
decode_result=$(perl -0777 -ne '
    if (/\x1b_Ga=T,f=100,i=99,c=\d+,r=\d+,C=1,q=2;(.*?)\x1b\\/s) {
        require MIME::Base64;
        my $bytes = MIME::Base64::decode_base64($1);
        print "len=" . length($bytes) . " magic=" . (substr($bytes,0,4) eq "\x89PNG" ? "PNG" : "NOTPNG");
    } else {
        print "NOMATCH";
    }
' "$raw_file")

if [[ "$decode_result" == *"magic=PNG"* ]]; then
    qa_pass "transmitted image payload decodes to a valid PNG (magic bytes correct): $decode_result"
else
    qa_fail "transmitted image payload decodes to a valid PNG" "$decode_result"
fi

qa_keys "ctrl-q"
qa_summary
