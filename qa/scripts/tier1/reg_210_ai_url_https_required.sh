#!/usr/bin/env bash
# QA-REG-210: "AI Completion: Setup" rejects a non-https API URL instead
# of silently saving it — see bugs.md P3 "AI API URL has no scheme
# enforcement, allowing silent plaintext transmission of the API key".
#
# The original bug: cmd_ai_setup's step-1 "API URL:" footer input
# accepted any non-empty string with no scheme check, then later steps
# save the API key to that URL via an Authorization header
# (AIComplete.pm). A mistyped/pasted http:// URL would silently transmit
# the key in plaintext with no warning. Fix: reject non-https:// URLs at
# setup time via the same show_error_message()/_user_error() pattern
# used elsewhere in Editor/Commands.pm, and never save the rejected
# value to preferences.
#
# Non-tautological: run against the pre-fix code (no scheme check in
# cmd_ai_setup) and every "rejected" assertion below fails -- the wizard
# happily proceeds to "Model:" and saves the http:// URL to
# preferences.json.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-210: AI Completion setup requires https:// API URL"

file=$(qa_tmpfile_nl "reg210.txt" "hello")
qa_start "$file"

open_setup() {
    qa_keys "ctrl-space"
    qa_send "AI Completion: Setup" 0.3
    qa_assert_expect "AI Completion: Setup" "palette lists 'AI Completion: Setup' command"
    qa_keys "enter"
    qa_assert_expect "API URL:" "step 1: API URL prompt opens"
}

# --- Reject: http:// (plaintext) URL ---
open_setup
qa_send "http://insecure.example.com/v1"
qa_keys "enter"

qa_assert_expect "https" "error message shown, mentions https requirement"

# The wizard must NOT have silently advanced to step 2 -- that would mean
# the invalid URL was treated as accepted.
qa_screen
if echo "$QA_SCREEN" | grep -qE "Model:"; then
    qa_fail "wizard does not advance to 'Model:' after a rejected URL" \
        "'Model:' prompt is showing -- the http:// URL was accepted"
else
    qa_pass "wizard does not advance to 'Model:' after a rejected URL"
fi

prefs_path="$QA_STATE_DIR/preferences.json"
qa_assert_file_not_contains "$prefs_path" "insecure\.example\.com" \
    "rejected http:// URL was never written to preferences.json"

# --- Reject: bare host with no scheme at all ---
open_setup
qa_send "example.com/v1"
qa_keys "enter"
qa_assert_expect "https" "error message shown for a schemeless URL too"
qa_assert_file_not_contains "$prefs_path" "\"example\.com/v1\"" \
    "schemeless URL was never written to preferences.json"

# --- Accept: well-formed https:// URL proceeds through the full wizard ---
open_setup
qa_send "https://api.qa-reg-210.example.invalid/v1"
qa_keys "enter"
qa_assert_expect "Model:" "step 2: Model prompt opens after a valid https:// URL"
qa_send "qa-reg-210-model"
qa_keys "enter"

qa_assert_expect "API Key:" "step 3: API Key prompt opens"
qa_send "sk-test-qa-reg-210-fake-key"
qa_keys "enter"

qa_assert_expect "AI Completion configured" "confirmation message shown for the accepted https:// URL"

qa_assert_file_exists "$prefs_path"
qa_assert_file_contains "$prefs_path" "https://api\\.qa-reg-210\\.example\\.invalid/v1" \
    "accepted https:// URL was saved to preferences.json"
qa_assert_file_not_contains "$prefs_path" '"ai_api_url":"http://' \
    "preferences.json never contains a saved plaintext http:// AI URL"

qa_keys "ctrl-q"
qa_summary
