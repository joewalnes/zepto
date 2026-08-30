#!/usr/bin/env bash
# QA-REG-175: Markdown inline-image spacer rows (the blank rows reserved
# below an inline image placement) fill with the real theme background,
# not a blank/missing color.
#
# Bug: Renderer.pm's image-spacer row handler read
# `$theme->color('editor_bg')` — no theme defines an `editor_bg` role (the
# real role is `bg`), and `Theme::color()` silently returns '' for an
# unknown role, so the spacer row's text-area cells never got an explicit
# background color escape code, leaving them showing whatever SGR state
# was still active from the gutter fill just before them (the wrong
# color, not "no color") in both themes. Found via code audit while
# investigating QA-REG-174 (see bugs.md 2026-08-30). Fixed to
# `$theme->color('bg')`.
#
# Requires a Kitty-graphics-capable TERM_PROGRAM for the image-spacer path
# to engage at all (Zepto::Terminal->supports_kitty_graphics()). hangon
# sessions do NOT inherit the client's shell environment (see qa_start's
# own comment in qa-helpers.sh), so TERM_PROGRAM must be set on the
# *invoked command itself* via `env`, not exported before calling hangon —
# this script therefore calls `hangon start` directly instead of
# qa_start.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-175: Image spacer row background color"

# Minimal valid 1x1 PNG (same bytes used by tests/renderer.t)
photo_path="$QA_TMPDIR/photo.png"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x01\x00\x00\x00\x007n\xf9\x24\x00\x00\x00\x0aIDATx\x9cb\x60\x01\x00\x00\x00\x05\x00\x01\xe9\x8a\xab\x6c\x00\x00\x00\x00IEND\xaeB\x60\x82' > "$photo_path"

md_path="$QA_TMPDIR/reg175.md"
cat > "$md_path" <<'EOF'
# Title
![photo](photo.png)
After image
EOF

hangon start process --name "$QA_SESSION" -- env TERM_PROGRAM=ghostty "$QA_ZEPTO" \
    --state-dir "$QA_STATE_DIR" --no-system-clipboard "$md_path"
sleep "$QA_RENDER_WAIT"

qa_assert_expect "Title" "markdown file is open"

tmux_sess=$(hangon list 2>/dev/null | awk -v n="$QA_SESSION" '$1==n {print $3}')
raw=$(tmux capture-pane -t "hangon-${tmux_sess}" -p -e 2>/dev/null)

# Row 5 (1-based: tab bar, ruler, "# Title", "![photo]...", then the first
# blank image-spacer row) must carry the real theme main bg (26,27,38 on
# the default dark theme). Before the fix, this row's text area carried
# NO explicit bg color of its own and showed the preceding gutter fill's
# color (22,22,30) bleeding through instead — this pattern only appears
# once the fill for the spacer row's own text area emits its own SGR code.
row5=$(echo "$raw" | sed -n '5p')
if echo "$row5" | grep -q '48;2;26;27;38'; then
    qa_pass "image spacer row carries the real theme bg color"
else
    qa_fail "image spacer row carries the real theme bg color" \
        "row5 raw bytes: $row5"
fi

qa_keys "ctrl-q"
qa_summary
