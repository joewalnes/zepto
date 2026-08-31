#!/usr/bin/env bash
# QA-REG-188: Clipboard paste no longer freezes the editor when the
# platform clipboard command hangs.
#
# Bug: Terminal.pm's paste_from_clipboard() did a bare blocking `<$fh>`
# slurp with no alarm()/timeout guard, unlike FindEngine.pm's
# MATCH_ALARM_SECS pattern. A wedged clipboard command (e.g. wl-paste
# with no reachable Wayland compositor over SSH, or a hung
# powershell.exe under WSL) would freeze the whole editor forever with
# no recovery path.
#
# Fix: guard the blocking read with the same alarm()-guard idiom
# (CLIPBOARD_PASTE_ALARM_SECS = 3s); on timeout, kill+reap the child and
# return undef (distinct from "" for an empty clipboard) so cmd_paste can
# surface a real "Paste failed: clipboard read timed out" message via the
# existing _user_error()/show_error_message() pattern. See bugs.md P1
# "Clipboard paste has no timeout" and tests/terminal.t for the unit-level
# real-timing proof of the Terminal.pm mechanism in isolation.
#
# This script reproduces the actual end-to-end hang via a real Ctrl+V in
# the running binary: it shadows the platform clipboard paste command
# (whichever one Terminal.pm's _detect_clipboard_commands would pick, on
# whatever platform this runs) with a fake that hangs for 30s -- far
# longer than the 3s alarm -- placed earlier in PATH than the real tool.
# All plausible branches (macOS pbpaste, X11 xclip/xsel, Wayland
# wl-paste) are faked so this reproduces correctly regardless of which
# platform/tools the runner actually has.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-188: Clipboard paste recovers from a hung clipboard command"

fakebin="$QA_TMPDIR/fakebin"
mkdir -p "$fakebin"

cat > "$fakebin/pbcopy" <<'FAKE'
#!/bin/sh
cat >/dev/null
FAKE
cat > "$fakebin/pbpaste" <<'FAKE'
#!/bin/sh
sleep 30
FAKE
cat > "$fakebin/xclip" <<'FAKE'
#!/bin/sh
case "$*" in
    *-o*) sleep 30 ;;
    *) cat >/dev/null ;;
esac
FAKE
cat > "$fakebin/xsel" <<'FAKE'
#!/bin/sh
case "$*" in
    *--output*) sleep 30 ;;
    *) cat >/dev/null ;;
esac
FAKE
cat > "$fakebin/wl-copy" <<'FAKE'
#!/bin/sh
cat >/dev/null
FAKE
cat > "$fakebin/wl-paste" <<'FAKE'
#!/bin/sh
sleep 30
FAKE
chmod +x "$fakebin"/*

file=$(qa_tmpfile_nl "reg188.txt" "before paste")

# Bypass qa_start's hardcoded --no-system-clipboard: that flag skips
# clipboard-command detection entirely (Terminal.pm never calls
# _detect_clipboard_commands), which would make this scenario
# unreachable. Launch directly instead, with the fake binaries shadowing
# the real ones via PATH -- confirmed PATH is inherited by
# hangon-launched processes for a freshly-started session.
PATH="$fakebin:$PATH" hangon start process --name "$QA_SESSION" -- \
    "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" "$file"
sleep "$QA_RENDER_WAIT"

start_ts=$(date +%s)
qa_keys "ctrl-v"

if qa_wait_screen 'Paste failed|timed out' 8; then
    elapsed=$(( $(date +%s) - start_ts ))
    qa_pass "paste failure/timeout message appeared within ${elapsed}s (no indefinite freeze)"
else
    qa_fail "paste failure/timeout message appeared within 8s" \
        "editor appears frozen, or silently swallowed the hang instead of surfacing an error"
fi

# The editor's main loop must still be responsive after the timeout --
# type something and confirm it lands, proving the process wasn't wedged.
qa_send "still alive"
qa_assert_expect "still alive" "editor remains responsive after the paste timeout (typed text landed)"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
