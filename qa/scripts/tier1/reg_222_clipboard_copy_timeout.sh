#!/usr/bin/env bash
# QA-REG-222: Clipboard copy no longer freezes the editor when the
# platform clipboard command hangs.
#
# Bug: Terminal.pm's copy_to_clipboard() wrote to the platform
# clipboard-copy command's pipe and called `close` on it with no
# alarm()/timeout guard, unlike paste_from_clipboard()'s
# CLIPBOARD_PASTE_ALARM_SECS pattern (QA-REG-188) or FindEngine.pm's
# MATCH_ALARM_SECS. `close` on a piped filehandle blocks until the child
# exits, so a wedged clipboard command (e.g. pbcopy/xclip/wl-copy stuck,
# or blocked on a full pipe with a slow/stuck consumer) would freeze the
# whole editor forever with no recovery path.
#
# Fix: guard the write+close with the same alarm()-guard idiom
# (CLIPBOARD_COPY_ALARM_SECS = 3s); on timeout, kill+reap the child and
# return undef (distinct from '' for "skipped, e.g. no system clipboard"
# and 1 for "ok") so cmd_cut/cmd_copy can surface a real
# "Cut/Copy: system clipboard write timed out" message via the existing
# _user_error()/show_error_message() pattern -- the internal
# clipboard/cut still completes either way. See bugs.md P1 "Clipboard
# copy has no timeout" and tests/terminal.t "copy_to_clipboard times out
# on a hung clipboard command" for the unit-level real-timing proof of
# the Terminal.pm mechanism in isolation.
#
# This script reproduces the actual end-to-end hang via a real Ctrl+C
# (copy) in the running binary: it shadows the platform clipboard-copy
# command (whichever one Terminal.pm's _detect_clipboard_commands would
# pick, on whatever platform this runs) with a fake that hangs for 30s --
# far longer than the 3s alarm -- placed earlier in PATH than the real
# tool. All plausible branches (macOS pbcopy, X11 xclip/xsel, Wayland
# wl-copy) are faked so this reproduces correctly regardless of which
# platform/tools the runner actually has. Paste commands are left as
# real no-ops (cat >/dev/null) since only the copy path is under test.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-222: Clipboard copy recovers from a hung clipboard command"

fakebin="$QA_TMPDIR/fakebin"
mkdir -p "$fakebin"

cat > "$fakebin/pbcopy" <<'FAKE'
#!/bin/sh
sleep 30
FAKE
cat > "$fakebin/pbpaste" <<'FAKE'
#!/bin/sh
cat >/dev/null
FAKE
cat > "$fakebin/xclip" <<'FAKE'
#!/bin/sh
case "$*" in
    *-o*) cat >/dev/null ;;
    *) sleep 30 ;;
esac
FAKE
cat > "$fakebin/xsel" <<'FAKE'
#!/bin/sh
case "$*" in
    *--output*) cat >/dev/null ;;
    *) sleep 30 ;;
esac
FAKE
cat > "$fakebin/wl-copy" <<'FAKE'
#!/bin/sh
sleep 30
FAKE
cat > "$fakebin/wl-paste" <<'FAKE'
#!/bin/sh
cat >/dev/null
FAKE
chmod +x "$fakebin"/*

file=$(qa_tmpfile_nl "reg222.txt" "copy me please")

# Bypass qa_start's hardcoded --no-system-clipboard: that flag skips
# clipboard-command detection entirely (Terminal.pm never calls
# _detect_clipboard_commands), which would make this scenario
# unreachable. Launch directly instead, with the fake binaries shadowing
# the real ones via PATH -- confirmed PATH is inherited by
# hangon-launched processes for a freshly-started session.
PATH="$fakebin:$PATH" hangon start process --name "$QA_SESSION" -- \
    "$QA_ZEPTO" --state-dir "$QA_STATE_DIR" "$file"
sleep "$QA_RENDER_WAIT"

# Select the whole line so cmd_copy has a selection to copy.
qa_keys "home"
qa_keys "shift-end"

start_ts=$(date +%s)
qa_keys "ctrl-c"

if qa_wait_screen 'Copy: system clipboard write timed out' 8; then
    elapsed=$(( $(date +%s) - start_ts ))
    qa_pass "copy timeout message appeared within ${elapsed}s (no indefinite freeze)"
else
    qa_fail "copy timeout message appeared within 8s" \
        "editor appears frozen, or silently swallowed the hang instead of surfacing an error"
fi

# The editor's main loop must still be responsive after the timeout --
# type something and confirm it lands, proving the process wasn't wedged.
qa_send "still alive"
qa_assert_expect "still alive" "editor remains responsive after the copy timeout (typed text landed)"

qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
