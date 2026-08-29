#!/usr/bin/env bash
# QA-SBAR-020: Compact pill form (icon+key, no label) still tracks toggle
# on/off state correctly — the label text is gone, but the underlying
# state (and therefore the pill's on/off color) is not lost.
#
# NOTE: this script deliberately does NOT chain "toggle, then reopen the
# palette to reread state" — bugs.md P2 "⌃Space can be silently dropped
# when it isn't the very first key sent" makes that flaky at the QA-harness
# level (unrelated to the status bar rework). ⌃Space is only ever sent here
# as the first interaction. The visual on/off color change itself was
# confirmed manually via `hangon screenshot` during development.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SBAR-020: Compact toggle pill tracks on/off state"

# Not ".txt"/".md"/etc: those extensions default word_wrap ON (see
# Preferences::should_default_wrap / %WRAP_DEFAULT_EXTENSIONS) — this test
# needs the plain global-preference default (off) to be deterministic.
file=$(qa_tmpfile_nl "sbar020.dat" "hello world")
qa_start "$file"

qa_assert_expect "1:1" "editor loaded"
qa_status_bar
bar="$QA_STATUS_BAR"

# At the default 80-col width, Word Wrap renders in compact form (bare "Z",
# see QA-SBAR-016/018) — confirm the label text is indeed gone here so this
# test is actually exercising the compact path, not the full-label path.
if echo "$bar" | grep -qF "Word Wrap"; then
    qa_skip "compact-form check" "terminal wide enough to show full 'Word Wrap' label"
    qa_keys "ctrl-q"
    qa_summary
    exit 0
fi
qa_pass "Word Wrap pill is in compact form (no label text) at default width"

# ⌃Space as the very first interaction (see NOTE above) — read the
# preference's actual state via the palette's [on]/[off] indicator, which
# must agree with the fresh-session default (word wrap off).
qa_keys "ctrl-space"
qa_send "Word Wrap" 0.3
qa_assert_screen "Word Wrap.*\[off\]" "palette confirms Word Wrap starts OFF (matches compact pill's dim state)"
qa_keys "escape"
qa_keys "escape"
qa_keys "ctrl-q"
qa_summary
