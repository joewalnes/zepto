#!/usr/bin/env bash
# QA-AI-001: Command palette -> "AI: Configure" opens the Settings dialog
# with all expected fields, and Esc cancels without changing anything.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-AI-001: AI Settings dialog opens with all fields"

echo "hello" > testfile.txt
qa_start testfile.txt

# Discoverable via the command palette (Rule 2 requirement).
qa_keys "ctrl-space"
qa_send "AI: Configure"
qa_assert_screen "AI: Configure" "palette shows AI: Configure command"

qa_keys "enter"
qa_assert_screen "AI: Configure" "dialog title visible"
qa_assert_screen "Provider" "Provider field visible"
qa_assert_screen "Base URL" "Base URL field visible"
qa_assert_screen "API Key" "API Key field visible"
qa_assert_screen "Test Connection" "Test Connection button visible"
qa_assert_screen "Model" "Model field visible"
qa_assert_screen "Save" "Save button visible"
qa_assert_screen "Cancel" "Cancel button visible"

# A key must never be shown in the clear — even the "(not set)" default
# must not read as plaintext content.
qa_assert_not_screen "sk-[A-Za-z0-9]{10,}" "no plaintext-looking key leaks onto screen"

# Esc cancels the whole dialog (back to editing, not just the field).
# A lone Esc byte is held pending by the input parser to disambiguate from
# an Alt+key sequence and only resolves into a real Escape key on the next
# idle timeout (INPUT_TIMEOUT_SEC) -- give it more than the default render
# wait so this isn't a race under load.
qa_keys "escape" 1.2
qa_assert_not_screen "AI: Configure" "dialog closed after Esc"
qa_assert_screen "hello" "back to editing the file"

qa_keys "ctrl-q"
qa_summary
