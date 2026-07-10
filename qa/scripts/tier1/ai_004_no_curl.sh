#!/usr/bin/env bash
# QA-AI-004: When curl is not on PATH, every AI entry point shows a clear
# "requires curl" message instead of crashing or silently doing nothing.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-AI-004: Graceful degradation when curl is missing"

echo "hello" > testfile.txt

# Build a PATH that mirrors every real system binary EXCEPT curl (rather
# than a near-empty PATH with just perl on it) -- an almost-empty PATH
# starves other things the terminal/runtime environment implicitly leans
# on and produces unrelated corruption unrelated to this test's actual
# question (confirmed while writing this script: a perl-only PATH broke
# Ctrl+Space input handling itself, nothing to do with curl).
fakebin="$QA_TMPDIR/fakebin"
mkdir -p "$fakebin"
for dir in /usr/local/bin /usr/bin /bin; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*; do
        b=$(basename "$f")
        [[ "$b" == "curl" ]] && continue
        [[ -e "$fakebin/$b" ]] && continue
        ln -sf "$f" "$fakebin/$b" 2>/dev/null || true
    done
done

if command -v curl >/dev/null 2>&1; then
    qa_pass "sanity: curl exists on the real PATH (so this test is meaningful)"
else
    qa_skip "curl availability sanity check" "curl not installed on this host at all"
fi
if [[ -x "$fakebin/curl" ]]; then
    qa_fail "fake PATH excludes curl" "curl unexpectedly present in $fakebin"
else
    qa_pass "fake PATH excludes curl"
fi

# hangon's tmux backend launders the environment (see qa_start's own
# comment block) -- bypass qa_start here and build the command directly so
# our restricted PATH actually reaches the zepto process, matching the
# same --state-dir discipline qa_start uses.
hangon stop "$QA_SESSION" 2>/dev/null || true
hangon start process --name "$QA_SESSION" -- \
    env PATH="$fakebin" \
    "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" testfile.txt
sleep "$QA_RENDER_WAIT"

qa_assert_screen "hello" "editor still launches fine with no curl on PATH"

# Entry point 1: opening the Settings dialog surfaces the message
# immediately (no crash, no silent no-op).
qa_keys "ctrl-space"
qa_send "AI: Configure"
qa_keys "enter"
qa_assert_screen "AI: Configure" "dialog still opens"
qa_assert_screen "curl.*not found on PATH" "dialog shows the curl-missing message"
qa_keys "escape" 1.2

# Entry point 2: pre-seed a fully "configured" state directly in the state
# store (bypassing the dialog, which requires a successful Test that also
# needs curl) and confirm the toggle command also reports the same clear
# error rather than pretending to enable.
cat > "$QA_STATE_DIR/preferences.json" <<JSON
{"ai_provider":"custom","ai_api_url":"http://127.0.0.1:1","ai_model":"test-model"}
JSON
cat > "$QA_STATE_DIR/secrets.json" <<JSON
{"ai_api_key":"test-key"}
JSON
chmod 600 "$QA_STATE_DIR/secrets.json"

# Restart manually the same way as above -- qa_restart can't express a
# custom PATH.
hangon stop "$QA_SESSION" 2>/dev/null || true
hangon start process --name "$QA_SESSION" -- \
    env PATH="$fakebin" \
    "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" testfile.txt
sleep "$QA_RENDER_WAIT"

qa_keys "ctrl-space"
qa_send "AI Completion"
qa_keys "enter"
qa_assert_screen "curl" "toggling AI on reports the curl-missing error"
qa_assert_not_screen "AI Completion: ON" "toggle never claims success without curl"

qa_keys "ctrl-q"
qa_summary
