#!/usr/bin/env bash
# QA-REG-169: ⌃Space falls back to the command palette when the cursor is
# mid-word but no real completion is available.
#
# Regression test for bugs.md P2 "⌃Space (open palette) can be silently
# dropped when it isn't the very first key sent". Root cause (confirmed via
# instrumented byte-level tracing, NOT an InputParser/Terminal timing
# issue): Editor.pm's handle_ctrl_char() space-handler treats "one word
# character before the cursor" as the trigger for "try completion instead
# of the palette" — but Completion::Controller::trigger() requires a 2+
# char prefix to produce results. A 1-char prefix makes trigger() dismiss
# immediately, leaving is_active() false, and the old code returned right
# there without ever falling back to cmd_open_palette() — so ⌃Space did
# nothing at all whenever the cursor happened to sit right after a single
# word character (e.g. after pressing → once from the start of a word).
#
# Fix: only skip the palette when a completion menu ACTUALLY opened
# (is_active() true after trigger()); otherwise always fall through to
# cmd_open_palette(). See QA-PAL-024 for the primary feature-level test
# case and QA-CPLT-021 for the (unrelated) cross-buffer completion test.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-169: Ctrl+Space palette fallback when mid-word completion is unavailable"

file=$(qa_tmpfile_nl "reg169.dat" "hello world")
qa_start "$file"

qa_assert_expect "1:1" "editor loaded, cursor at start"

# Move cursor to just after "h" — exactly one word char precedes the
# cursor, which is the condition that used to swallow ⌃Space silently
# (the prefix "h" is too short for any real completion to fire).
qa_keys "right"
qa_assert_cursor_at "1:2" "cursor is right after the single word char 'h'"

qa_keys "ctrl-space"
qa_assert_expect "⌃␣ Commands" "palette opened instead of silently doing nothing"

# Confirm subsequent typing filters the palette rather than landing as
# literal text in the document (the corruption symptom from bugs.md,
# reproduced with the exact "hWord Wrapello world" artifact).
qa_send "Word Wrap"
qa_assert_screen "Word Wrap" "typed text filters the palette list"
qa_assert_not_screen "hWord" "typed text did NOT land as literal document text"

qa_keys "escape" 0.3
# Poll (rather than a flat sleep+assert) so this doesn't flake under a
# slow/loaded render — wait for the document text to reappear, which only
# happens once the palette has actually closed.
qa_wait_screen "hello world" 3 >/dev/null
qa_assert_not_screen "⌃␣ Commands" "palette closed"

# Document must be untouched — still exactly "hello world", no stray
# characters inserted anywhere during the failed-then-fixed interaction.
qa_assert_screen "hello world" "document content is unmodified"

qa_keys "ctrl-q"
qa_summary
