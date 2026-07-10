#!/usr/bin/env bash
# QA-AI-002: Configure against a local mock server, then enable AI
# completion -> one-time consent prompt naming the exact endpoint -> Y
# enables it (pill/state flips to [on]) and remembers consent per-endpoint.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-AI-002: Configure + consent + enable flow"

qa_ai_mock_start "qa_002_completion"

echo "hello" > testfile.txt
qa_start testfile.txt

# --- Configure ---
qa_keys "ctrl-space"
qa_send "AI: Configure"
qa_keys "enter"
qa_assert_screen "AI: Configure" "dialog open"

qa_keys "tab"                      # -> Base URL
qa_keys "ctrl-a"
qa_keys "backspace"
qa_send "$QA_AI_MOCK_URL"
qa_assert_screen "127.0.0.1" "base URL field shows the mock server URL"

qa_keys "tab"                      # -> API Key
qa_send "qa-test-key-9999"
qa_assert_screen "9999" "API key shows last 4 chars unmasked"
qa_assert_not_screen "qa-test-key" "API key prefix is masked, not shown in the clear"

qa_keys "tab"                      # -> Test Connection
qa_keys "enter"
qa_expect_screen "OK - 3 models" 8 && qa_pass "Test Connection succeeds against the mock server" \
    || qa_fail "Test Connection succeeds against the mock server"

qa_keys "tab"                      # -> Model (already preselected)
qa_keys "tab"                      # -> Save
qa_keys "enter"
qa_assert_screen "AI: configured" "Save confirms configuration"
qa_assert_not_screen "AI: Configure" "dialog closed after Save"

# --- Enable: one-time consent naming the exact endpoint ---
qa_keys "ctrl-space"
qa_send "AI Completion"
qa_assert_screen "\[off\]" "AI Completion starts OFF (ships disabled every launch)"
qa_keys "enter"
# The wide consent sentence can wrap across two terminal rows at 80 cols
# (the trailing "Enable" button label wraps); assert on the part of the
# sentence guaranteed to render on a single row: the endpoint being named.
qa_assert_screen "Sends text near your cursor to.*${QA_AI_MOCK_URL}.*as you type" "consent prompt names the exact endpoint"
qa_assert_screen "Cancel N" "consent prompt offers a Cancel option"

qa_send "y"
qa_assert_screen "AI Completion: ON" "consent accepted -> AI Completion ON"

# --- Consent remembered per-endpoint: re-toggling off/on for the SAME
# endpoint must not re-prompt. ---
qa_keys "ctrl-space"
qa_send "AI Completion"
qa_assert_screen "\[on\]" "palette reflects ON state"
qa_keys "enter"
qa_assert_screen "AI Completion: OFF" "toggle off needs no confirmation"

# Toggle commands keep the palette open (per UI guidelines) -- close it
# explicitly before reopening, since Ctrl+Space while the palette is
# already open closes it rather than refreshing it (a second Ctrl+Space
# here would otherwise land back in the editor and type the next
# "AI Completion" search text straight into the document).
qa_keys "escape" 1.2

qa_keys "ctrl-space"
qa_send "AI Completion"
qa_keys "enter"
qa_assert_screen "AI Completion: ON" "re-enabling the SAME endpoint does not re-prompt for consent"

qa_keys "ctrl-q"

qa_assert_file_contains "$QA_STATE_DIR/preferences.json" "ai_consented_urls" "consent persisted in preferences"
qa_assert_file_contains "$QA_STATE_DIR/secrets.json" "qa-test-key-9999" "API key persisted to secrets"

# Secrets file must be 0600 (never world/group readable).
if [[ -f "$QA_STATE_DIR/secrets.json" ]]; then
    mode=$(stat -c '%a' "$QA_STATE_DIR/secrets.json" 2>/dev/null || stat -f '%Lp' "$QA_STATE_DIR/secrets.json" 2>/dev/null)
    if [[ "$mode" == "600" ]]; then
        qa_pass "secrets.json is mode 600"
    else
        qa_fail "secrets.json is mode 600" "got mode: $mode"
    fi
fi

qa_summary
