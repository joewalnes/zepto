#!/usr/bin/env bash
# QA-AI-003: With AI completion enabled against a mock server that returns
# a fixed completion, typing shows ghost text with the mock's exact text,
# Esc dismisses it (proving it's virtual, not committed), and Tab accepts
# it into the real, saved buffer content.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-AI-003: Ghost text renders mock completion, Tab accepts"

qa_ai_mock_start "qa_ghost_suggestion"

printf 'line one\nline two\n' > testfile.txt
qa_start testfile.txt

# --- Configure (same flow as QA-AI-002) ---
qa_keys "ctrl-space"
qa_send "AI: Configure"
qa_keys "enter"
qa_keys "tab"
qa_keys "ctrl-a"
qa_keys "backspace"
qa_send "$QA_AI_MOCK_URL"
qa_keys "tab"
qa_send "qa-test-key-0000"
qa_keys "tab"
qa_keys "enter"
qa_expect_screen "OK - 3 models" 8 && qa_pass "Test Connection succeeds" || qa_fail "Test Connection succeeds"
qa_keys "tab"
qa_keys "tab"
qa_keys "enter"
qa_assert_screen "AI: configured" "Saved"

# --- Enable ---
qa_keys "ctrl-space"
qa_send "AI Completion"
qa_keys "enter"
qa_send "y"
qa_assert_screen "AI Completion: ON" "enabled"

# --- Move to a deterministic, empty cursor position: Go to Line puts the
# cursor exactly at the end of line 2 ("line two" is 8 chars -> col 9),
# then Enter creates a fresh, empty line 3 to type into. ---
qa_keys "ctrl-g"
qa_keys "ctrl-a" 0.1
qa_send "2:9"
qa_keys "enter"
qa_assert_screen "2:9" "cursor jumped to end of line 2"
qa_keys "enter"

# --- Trigger and observe ghost text ---
# Poll rather than assume a fixed sleep is enough: the AI completion path
# has its own debounce (0.5s) on top of the mock server round-trip.
qa_send "zzzqqqtrig" 0.1
qa_expect_screen "qa_ghost_suggestion" 5 && qa_pass "ghost text shows the mock server's exact completion" \
    || qa_fail "ghost text shows the mock server's exact completion"

# --- Esc dismisses (proves it's virtual, not yet in the buffer) ---
# A lone Esc byte is held pending by the input parser to disambiguate from
# an Alt+key sequence and only resolves on the next idle timeout -- give
# it more than the default render wait so this isn't a race under load.
qa_keys "escape" 1.2
qa_assert_not_screen "qa_ghost_suggestion" "Esc dismissed the ghost text"
qa_assert_screen "zzzqqqtrig" "typed prefix is still there (dismiss didn't touch real content)"

# --- Re-trigger (dismiss starts a 1s cooldown; a further keystroke after
# that re-arms it) and accept with Tab this time ---
qa_send "x" 0.1
qa_expect_screen "qa_ghost_suggestion" 5 && qa_pass "ghost text reappears after re-trigger" \
    || qa_fail "ghost text reappears after re-trigger"
qa_keys "tab"
qa_assert_screen "qa_ghost_suggestion" "accepted text still visible after Tab (now real, not ghost)"

qa_keys "ctrl-s"
qa_keys "ctrl-q"

qa_assert_file_contains "testfile.txt" "qa_ghost_suggestion" "accepted completion persisted to the saved file (real content, not just ghost)"

qa_summary
