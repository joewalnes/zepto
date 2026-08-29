#!/usr/bin/env bash
# QA-MD-009: Markdown emphasis delimiters render dimmed (visual)
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-MD-009: Dim Markdown formatting delimiters (visual)"

file=$(qa_tmpfile_nl "md012.md" 'Plain text baseline, no formatting at all.

This is **bold text** and this is *italic text*.

This is ***bold and italic*** combined.

This is ~~strikethrough text~~ here.

This is ==highlighted text== here.

Mixed: **bold**, *italic*, ~~struck~~, ==marked==, plain.')
qa_start "$file"
sleep 0.5

shot="$QA_TMPDIR/md_dim_delimiters.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file in a terminal text editor. Verify the emphasis delimiter characters (the ** and * around bold/italic text, the ~~ around strikethrough text, and the == around highlighted text) are rendered in a FAINT, LOW-CONTRAST color -- much closer to the dark background color than to the plain body text color. Meanwhile the STYLED CONTENT inside the delimiters (the words 'bold text', 'italic text', 'bold and italic', 'strikethrough text', 'highlighted text') should be clearly PROMINENT -- normal or brighter contrast, with bold/italic/strikethrough/highlight styling clearly visible. The delimiter punctuation characters must be visibly dimmer/fainter than both the plain 'Plain text baseline' line and the styled words they surround -- this is the core thing to verify. All delimiter characters (**, *, ~~, ==) must still be present/visible on screen, just dim, not invisible or removed." \
    "Emphasis delimiters render dim/faint while styled content stays prominent"

qa_keys "ctrl-t"
sleep 0.5
shot_light="$QA_TMPDIR/md_dim_delimiters_light.png"
qa_screenshot "$shot_light"

qa_assert_visual "$shot_light" \
    "This shows the same Markdown file in LIGHT theme (white/light background). Verify the same thing as before but now against a light background: the ** * ~~ == emphasis delimiter characters should be a FAINT LIGHT GRAY, much closer to the white background than to the plain black/dark body text, while the styled content they surround (bold/italic/strikethrough/highlighted words) remains clearly prominent and readable." \
    "Emphasis delimiters render dim/faint in light theme too"

qa_keys "ctrl-q"
qa_summary
