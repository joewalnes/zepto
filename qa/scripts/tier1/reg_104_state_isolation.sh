#!/usr/bin/env bash
# QA-REG-104: QA harness state isolation survives hangon/tmux env laundering
#
# hangon's tmux backend spawns commands via `tmux new-session` with no env
# forwarding: the pane gets the tmux SERVER's environment (captured when the
# first-ever hangon call started the server), not the calling test's. Before
# the qa_start fix, `export ZEPTO_STATE_DIR=...` from qa_setup silently
# never reached zepto — every test's zepto shared one stale state dir, and
# StateStore's cross-instance mtime sync live-poisoned running sessions
# whenever any concurrent test toggled a persisted preference (auto-pairs,
# nerd font, ...). That was the true root cause of the historically flaky
# QA-EDIT-020 / QA-MS-012 full-run failures. qa_start now passes
# --state-dir on the command line and forwards/clears ZEPTO_* env via an
# `env` wrapper. This test regression-guards both directions.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-104: state isolation through hangon/tmux"

# Direction 1: with NO ZEPTO_NERD_FONT in this test's environment, zepto
# must start with its default (nerd font ON) — even if a stale
# ZEPTO_NERD_FONT=0 is lurking in the tmux server's laundered env or a
# previous test persisted nerd_font=0 to a leaked shared state dir.
file=$(qa_tmpfile_nl "reg104.txt" "hello isolation")
qa_start "$file"
qa_screen
if echo "$QA_SCREEN" | head -1 | grep -qF "◢"; then
    qa_pass "fresh state dir: nerd font defaults ON (no stale env/state leak)"
else
    qa_fail "fresh state dir: nerd font defaults ON (no stale env/state leak)" \
        "$(echo "$QA_SCREEN" | head -1)"
fi
qa_keys "ctrl-q"
qa_stop
sleep 0.3

# Direction 2: a ZEPTO_* var exported by THIS test must actually reach
# zepto (qa_start's env wrapper), despite tmux not forwarding environments.
export ZEPTO_NERD_FONT=0
qa_start "$file"
qa_screen
if echo "$QA_SCREEN" | head -1 | grep -qF "/"; then
    qa_pass "exported ZEPTO_NERD_FONT=0 reached zepto through hangon/tmux"
else
    qa_fail "exported ZEPTO_NERD_FONT=0 reached zepto through hangon/tmux" \
        "$(echo "$QA_SCREEN" | head -1)"
fi
unset ZEPTO_NERD_FONT

qa_keys "ctrl-q"
qa_summary
