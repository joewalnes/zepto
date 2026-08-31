#!/usr/bin/env bash
# QA-REG-194: AI API key is written with restricted permissions from the
# moment of creation — see bugs.md P2 "AI API key briefly written
# world-readable before chmod 0600 catches up".
#
# The exact race window (file world-readable between open() and the
# later chmod 0600) is a unit-level concern verified deterministically
# and exhaustively by tests/state_store_secrets_race.t, which intercepts
# the file-creation syscall itself — a real terminal-driven QA script
# can't observe a microsecond-scale race like that. This script instead
# verifies the feature end-to-end from the UI a real user would use
# (Command Palette → "AI Completion: Setup"), confirming the flow is
# discoverable and that the resulting secrets.json file on disk ends up
# at the correct restricted mode (0600), not the default umask mode the
# original bug would have left behind.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-194: AI Setup writes secrets.json at mode 0600"

# A permissive umask so a regression to a plain `open` (default mode
# 0666) would leave a clearly wrong final mode, same technique used in
# tests/state_store_secrets_race.t.
umask 0022

file=$(qa_tmpfile_nl "reg194.txt" "hello")
qa_start "$file"

# Discoverability: reachable via the command palette.
qa_keys "ctrl-space"
qa_send "AI Completion: Setup" 0.3
qa_assert_expect "AI Completion: Setup" "palette lists 'AI Completion: Setup' command"
qa_keys "enter"

qa_assert_expect "API URL:" "step 1: API URL prompt opens"
qa_send "https://example.invalid/v1"
qa_keys "enter"

qa_assert_expect "Model:" "step 2: Model prompt opens"
qa_send "test-model"
qa_keys "enter"

qa_assert_expect "API Key:" "step 3: API Key prompt opens"
qa_send "sk-test-qa-reg-194-fake-key"
qa_keys "enter"

qa_assert_expect "AI Completion configured" "confirmation message shown"

secrets_path="$QA_STATE_DIR/secrets.json"
qa_assert_file_exists "$secrets_path"
qa_assert_file_contains "$secrets_path" "sk-test-qa-reg-194-fake-key" "secrets.json contains the configured API key"

if [[ -f "$secrets_path" ]]; then
    mode=$(perl -e 'print sprintf("%04o", (stat($ARGV[0]))[2] & 07777)' "$secrets_path")
    if [[ "$mode" == "0600" ]]; then
        qa_pass "secrets.json is mode 0600 (not the permissive umask default)"
    else
        qa_fail "secrets.json is mode 0600" "actual mode: $mode"
    fi
fi

qa_keys "ctrl-q"
qa_summary
