#!/usr/bin/env bash
# ===========================================================================
# qa-helpers.sh — shared utilities for Zepto QA test scripts
# ===========================================================================
# Source this at the top of every test script:
#   source "$(dirname "$0")/../../lib/qa-helpers.sh"
# ===========================================================================

set -euo pipefail

# Absolute path to this file's directory (qa/lib), resolved ONCE at source
# time, before qa_setup() below cd's into a per-test tmpdir. Functions that
# need to find sibling files (ai_mock_server.pl, llm-judge.sh) later, at
# CALL time, must use this instead of re-deriving `dirname "${BASH_SOURCE[0]}"`
# on demand — BASH_SOURCE preserves whatever (often relative) path this file
# was `source`d with, and re-resolving a relative path after cwd has
# changed silently breaks (see bugs.md).
_QA_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

QA_ZEPTO="${QA_ZEPTO:-./zepto}"
QA_SESSION="zqa_$$"
QA_RENDER_WAIT="${QA_RENDER_WAIT:-0.4}"
QA_TMPDIR=""
QA_PASSED=0
QA_FAILED=0
QA_SKIPPED=0
QA_TEST_NAME="${QA_TEST_NAME:-$(basename "$0" .sh)}"
QA_TIER="${QA_TIER:-1}"

# Internal tracking for auto-cleanup
_QA_ORIG_DIR=""
_QA_PROJECT_DIR=""
_QA_AI_MOCK_PID=""

_RED=$'\033[31m'
_GREEN=$'\033[32m'
_YELLOW=$'\033[33m'
_CYAN=$'\033[36m'
_DIM=$'\033[2m'
_RESET=$'\033[0m'

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

qa_setup() {
    QA_TMPDIR=$(mktemp -d /tmp/zepto_qa_XXXXXX)
    _QA_ORIG_DIR="$PWD"

    # Isolated state dir per test (no cross-test preference pollution)
    QA_STATE_DIR="$QA_TMPDIR/.zepto_state"
    mkdir -p "$QA_STATE_DIR"
    export ZEPTO_STATE_DIR="$QA_STATE_DIR"

    # Resolve QA_ZEPTO to absolute path (needed before any cd)
    QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"

    if ! command -v hangon &>/dev/null; then
        echo "${_RED}ERROR: hangon not found. Install: brew install joewalnes/tap/hangon${_RESET}" >&2
        exit 1
    fi
    if [[ ! -x "$QA_ZEPTO" ]]; then
        echo "${_RED}ERROR: $QA_ZEPTO not found. Run 'make build' first.${_RESET}" >&2
        exit 1
    fi
    hangon stop "$QA_SESSION" 2>/dev/null || true

    # Systemic leak guard: start every test inside its own auto-cleaned
    # tmpdir, NOT wherever the runner happened to invoke it from (the repo
    # root under `make qa`). Any script that writes relative-path scratch
    # files without cd-ing somewhere first now leaks into $QA_TMPDIR (wiped
    # on exit) instead of the repository. QA_ZEPTO was resolved to an
    # absolute path above, before this cd, so ./zepto still resolves.
    cd "$QA_TMPDIR" || exit 1
}

qa_cleanup() {
    hangon stop "$QA_SESSION" 2>/dev/null || true
    qa_ai_mock_stop
    # Restore original directory if we cd'd somewhere
    if [[ -n "$_QA_ORIG_DIR" ]]; then
        cd "$_QA_ORIG_DIR" 2>/dev/null || true
    fi
    if [[ -n "$QA_TMPDIR" && -d "$QA_TMPDIR" ]]; then
        rm -rf "$QA_TMPDIR"
    fi
    if [[ -n "$_QA_PROJECT_DIR" && -d "$_QA_PROJECT_DIR" ]]; then
        rm -rf "$_QA_PROJECT_DIR"
    fi
}
trap qa_cleanup EXIT

# ---------------------------------------------------------------------------
# Session management
# ---------------------------------------------------------------------------

# Start zepto in a hangon session
#   qa_start [args...]
#
# CRITICAL ISOLATION NOTE: hangon runs the command inside a shared tmux
# server (`tmux new-session` with no env forwarding — see backend_process.go
# in joewalnes/hangon). tmux gives new panes the SERVER's environment,
# captured when the first-ever hangon call started the server — NOT the
# calling test's environment. So plain `export ZEPTO_STATE_DIR=...` (or
# ZEPTO_NERD_FONT etc.) from a test script silently never reaches zepto:
# every test's zepto instead shares whatever stale ZEPTO_STATE_DIR the tmux
# server happened to capture. Combined with StateStore's cross-instance
# mtime sync (prefs live-reload when another instance writes them), one
# test toggling a preference (auto-pairs off, nerd font off, ...) poisoned
# every OTHER concurrently-running test's zepto mid-session. This was the
# real root cause of the historically flaky edit_020/ms_012 full-run
# failures. Defenses, in order:
#   1. Pass --state-dir on the COMMAND LINE (immune to env laundering).
#   2. Explicitly forward the caller's ZEPTO_* env vars via an `env`
#      wrapper on the command line, so tests like cli_010 (ZEPTO_NERD_FONT)
#      and cli_011 (ZEPTO_TREE) actually test what they think they test.
qa_start() {
    # Forward caller's ZEPTO_* environment through the command line. The
    # leading -u flags first CLEAR any stale ZEPTO_* vars the tmux server's
    # laundered environment might inject into the pane (e.g. a stale
    # ZEPTO_NERD_FONT=0 donated by whichever long-dead test started the
    # server); the caller's own values are then re-applied explicitly.
    local envargs=(-u ZEPTO_NERD_FONT -u ZEPTO_TREE -u ZEPTO_STATE_DIR)
    local kv
    while IFS= read -r kv; do
        [[ -n "$kv" ]] && envargs+=("$kv")
    done < <(env | grep '^ZEPTO_' || true)

    local cmd=(env "${envargs[@]}" "$QA_ZEPTO" --state-dir "$QA_STATE_DIR")

    # hangon's session registry (~/.hangon/state.json) is written with a
    # plain, non-atomic os.WriteFile — under enough concurrent `hangon`
    # invocations (many tier1 scripts starting sessions around the same
    # time), a reader can observe a torn/truncated write and hangon exits
    # with "corrupt state file ... unexpected end of JSON input". This is a
    # transient race in the harness tool itself, not a Zepto bug. Retry a
    # couple of times before giving up so a rare torn-write doesn't fail an
    # otherwise-passing test.
    local attempt
    for attempt in 1 2 3; do
        if hangon start process --name "$QA_SESSION" -- "${cmd[@]}" "$@"; then
            sleep "$QA_RENDER_WAIT"
            return 0
        fi
        hangon stop "$QA_SESSION" 2>/dev/null || true
        sleep 0.3
    done
    # Final attempt — let its exit code/output surface normally on failure.
    hangon start process --name "$QA_SESSION" -- "${cmd[@]}" "$@"
    sleep "$QA_RENDER_WAIT"
}

# Stop the current session
qa_stop() {
    hangon stop "$QA_SESSION" 2>/dev/null || true
}

# Restart zepto (quit + relaunch). Same state dir, fresh session.
#   qa_restart [args...]
# Use after qa_keys "ctrl-q" to test preference persistence, etc.
qa_restart() {
    qa_stop
    sleep 0.3
    qa_start "$@"
}

# Check if session is alive (exit 0 = alive)
qa_alive() {
    hangon alive "$QA_SESSION" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Project & git helpers
# ---------------------------------------------------------------------------

# Create a project directory and cd into it. Auto-cleaned on exit.
# Sets QA_PROJECT_DIR to the directory path. QA_ZEPTO is already absolute.
#
#   qa_project
#   echo "content" > "$QA_PROJECT_DIR/file.txt"   # or just: > file.txt (cwd)
#   qa_start file.txt
#
# MUST be called directly, NEVER via command substitution. The old
# documented API — `dir=$(qa_project)` — was catastrophically broken:
# $(...) runs the function in a SUBSHELL, so the cd (and the cleanup
# tracking variable) never affected the calling script. Every caller kept
# running in its original cwd — the repo root under `make qa` — where its
# relative-path file writes clobbered tracked repo files and, via
# qa_git_repo, `git add . && git commit` created stray commits IN THE ZEPTO
# REPO ITSELF (and `git config user.*` rewrote the repo's local git
# config). Deliberately nothing is echoed here so any legacy
# `dir=$(qa_project)` call gets an empty string and fails fast on first
# use ("/file.txt" is unwritable) instead of silently polluting the repo.
qa_project() {
    _QA_PROJECT_DIR=$(mktemp -d /tmp/zepto_qa_proj_XXXXXX)
    cd "$_QA_PROJECT_DIR" || exit 1
    QA_PROJECT_DIR="$_QA_PROJECT_DIR"
}

# Create a git repo project directory. Cd into it. Sets QA_PROJECT_DIR.
# Initializes git with a local test identity (no dependency on a global
# git user — fresh CI runners have none).
#
#   qa_git_repo
#   echo "content" > file.txt && git add . && git commit -m "init"
#
# Same warning as qa_project: call directly, never via $(...).
qa_git_repo() {
    qa_project
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
}

# ---------------------------------------------------------------------------
# AI completion mock server
# ---------------------------------------------------------------------------
# Starts a local, plain-HTTP, OpenAI-compatible mock server
# (qa/lib/ai_mock_server.pl — core Perl, no CPAN) for AI Settings /
# ghost-text completion QA scripts. Never touches the real network.
#
#   qa_ai_mock_start [completion_text]
#     Picks a free localhost port, starts the server, waits for it to
#     report ready (bounded), and sets QA_AI_MOCK_URL (e.g.
#     "http://127.0.0.1:54321"). Auto-stopped by qa_cleanup on exit.
#
#   qa_ai_mock_stop
#     Stops the server early (also called automatically at exit).
QA_AI_MOCK_URL=""
qa_ai_mock_start() {
    local completion_text="${1:-mock_completion_text}"
    local server_script="$_QA_HELPERS_DIR/ai_mock_server.pl"

    # Pick a free port by asking the OS for one, then race to bind it —
    # good enough for single-host QA runs (retry a couple of times if two
    # scripts race for the same port).
    local port attempt
    for attempt in 1 2 3; do
        port=$(perl -MIO::Socket::INET -e '
            my $s = IO::Socket::INET->new(Listen => 1, LocalAddr => "127.0.0.1", LocalPort => 0, ReuseAddr => 1);
            print $s->sockport(); ')
        local log="$QA_TMPDIR/ai_mock_server.$port.log"
        perl "$server_script" "$port" "$completion_text" > "$log" 2>&1 &
        _QA_AI_MOCK_PID=$!
        local deadline=$(( $(date +%s) + 5 ))
        while [[ $(date +%s) -lt $deadline ]]; do
            grep -q "^READY$" "$log" 2>/dev/null && break
            kill -0 "$_QA_AI_MOCK_PID" 2>/dev/null || break
            sleep 0.05
        done
        if grep -q "^READY$" "$log" 2>/dev/null; then
            QA_AI_MOCK_URL="http://127.0.0.1:$port"
            return 0
        fi
        kill "$_QA_AI_MOCK_PID" 2>/dev/null || true
        _QA_AI_MOCK_PID=""
    done
    echo "${_RED}ERROR: could not start ai_mock_server.pl${_RESET}" >&2
    return 1
}

qa_ai_mock_stop() {
    if [[ -n "$_QA_AI_MOCK_PID" ]]; then
        kill "$_QA_AI_MOCK_PID" 2>/dev/null || true
        wait "$_QA_AI_MOCK_PID" 2>/dev/null || true
        _QA_AI_MOCK_PID=""
    fi
}

# Portable sed -i (macOS vs GNU)
qa_sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

# hangon's session state (~/.hangon/state.json) is written non-atomically,
# so under parallel runner load `hangon keys`/`hangon send` intermittently
# fail with exit 1/2 ("session not found", torn-JSON reads) or misroute to
# a stale "default" session — killing set -e scripts mid-run and producing
# ghost CI failures (keys silently never delivered). Until hangon writes
# state atomically, retry delivery a few times with backoff. See bugs.md
# "[Testing hazard] hangon state.json races under parallel load".
_qa_hangon_retry() {
    local attempt
    for attempt in 1 2 3; do
        if hangon "$@"; then
            return 0
        fi
        sleep 0.3
    done
    echo "qa-helpers: hangon $1 failed after 3 attempts (session=$QA_SESSION)" >&2
    return 1
}

qa_send() {
    _qa_hangon_retry send "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

# hangon's `send` (both argv and --stdin forms) fails outright — exit
# status 2, "exit status 1" printed to stderr, nothing sent — whenever the
# text to type STARTS WITH A HYPHEN ('-'), e.g. typing a Markdown bullet
# "- item" or any leading flag-like text. Confirmed on both forms; `--`
# as an explicit end-of-flags marker does not help. Under this file's
# `set -e`, calling plain `qa_send` with such text silently aborts the
# whole script (see bugs.md "[Testing hazard] hangon send fails on
# leading-hyphen text").
#
# Workaround: type a harmless one-char prefix first (so the string hangon
# sees doesn't start with '-'), then step back and remove just that
# prefix char via Left*N + Backspace + Right*N — NOT Home+Delete, which
# would jump to column 0 and delete the wrong character if the cursor
# didn't start the line (Home always jumps to the line's start, not to
# "where we started typing"). This way the cursor ends up in the same
# place it would have if the leading-hyphen text had been typed directly.
# Use this instead of qa_send whenever the text might start with '-'.
qa_send_safe() {
    local text="$1"
    if [[ "$text" == -* ]]; then
        local len=${#text}
        hangon send "$QA_SESSION" "x$text"
        for ((i = 0; i < len; i++)); do hangon keys "$QA_SESSION" "left" >/dev/null; done
        hangon keys "$QA_SESSION" "backspace" >/dev/null
        for ((i = 0; i < len; i++)); do hangon keys "$QA_SESSION" "right" >/dev/null; done
    else
        hangon send "$QA_SESSION" "$text"
    fi
    sleep "${2:-$QA_RENDER_WAIT}"
}

qa_keys() {
    _qa_hangon_retry keys "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

# Send raw escape sequences
qa_raw() {
    _qa_hangon_retry send "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

qa_raw_stdin() {
    hangon send "$QA_SESSION" --stdin
    sleep "${1:-$QA_RENDER_WAIT}"
}

qa_sendline() {
    hangon sendline "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

qa_expect() {
    local pattern="$1"
    local timeout="${2:-5}"
    # hangon expect dumps the raw bytes it read (including ANSI escape
    # sequences and OSC clipboard payloads) to stdout while waiting for a
    # match — noise nobody wants in a QA report. Callers only care about
    # the exit code (0 = matched, 1 = timed out), so discard stdout too.
    hangon expect "$QA_SESSION" "$pattern" --timeout "$timeout" >/dev/null 2>&1
}

# Wait until the rendered SCREEN (not the raw output stream) matches a
# grep pattern, polling up to a timeout. Prefer this over qa_expect when
# the pattern is adjacent visible characters (e.g. "()"): in the raw output
# stream ANSI color/cursor escapes can be interleaved between characters
# that appear adjacent on screen, so a stream regex can miss them. Exit 0 =
# matched (and QA_SCREEN holds the matching capture), 1 = timed out.
#   qa_expect_screen PATTERN [TIMEOUT_SECONDS] [GREP_FLAG]
# GREP_FLAG defaults to -E (extended regex); pass -F for a literal string.
qa_expect_screen() {
    local pattern="$1"
    local timeout="${2:-5}"
    local grep_flag="${3:--E}"
    local deadline=$(( $(date +%s) + timeout ))
    while true; do
        qa_screen
        if echo "$QA_SCREEN" | grep -q "$grep_flag" -- "$pattern"; then
            return 0
        fi
        [[ $(date +%s) -ge $deadline ]] && return 1
        sleep 0.2
    done
}

# ---------------------------------------------------------------------------
# Mouse
# ---------------------------------------------------------------------------

# Move mouse to position without clicking (triggers hover)
#   qa_hover 40 10
qa_hover() {
    local x="$1" y="$2"
    # SGR mouse motion: ESC [ < 35 ; x ; y M (35 = motion, no button)
    qa_raw "$(printf '\x1b[<35;%d;%dM' "$x" "$y")"
}

# ---------------------------------------------------------------------------
# Raw SGR mouse injection (qa_mouse_*)
# ---------------------------------------------------------------------------
# hangon's built-in `mouse-click`/`mouse-drag` subcommands encode the SGR
# press/release final byte backwards (press as lowercase 'm', release as
# uppercase 'M') relative to the xterm standard. Zepto's InputParser follows
# the real standard (uppercase M = press, lowercase m = release), so button
# presses driven through `hangon mouse-click`/`mouse-drag` land on the wrong
# event — e.g. a drag's initial press is read as a release (no-op), the
# button-held motion events are then dropped because mouse_button_down was
# never set, and the trailing "release" is read as a press at the final
# coordinate. See qa/scripts/tier1/ms_012_drag_tree_border.sh history.
#
# These helpers bypass that bug entirely by writing the correct SGR bytes
# straight into the session via `hangon send SESSION --stdin`, which is a
# dumb literal byte-forwarder (tmux send-keys -l under the hood) and does
# not go through hangon's mouse encoder. Coordinates are 1-based terminal
# cells, matching hangon's own convention.
#
#   qa_mouse_press  X Y [BUTTON]   # BUTTON: 0=left(default) 1=middle 2=right
#   qa_mouse_drag   X Y [BUTTON]   # motion event while BUTTON is held
#   qa_mouse_release X Y [BUTTON]
#   qa_mouse_click  X Y [BUTTON]   # press + release at the same cell
#   qa_mouse_scroll X Y up|down [N]

_qa_mouse_raw() {
    # Tolerant of transient hangon failures (its non-atomic state.json can
    # briefly lose track of sessions under parallel load — see bugs.md):
    # under the helpers' `set -e`, an unguarded failure here would kill the
    # whole script with zero diagnostics, whereas letting the test's own
    # assertions fail produces an actionable report.
    printf '%s' "$1" | hangon send "$QA_SESSION" --stdin || true
}

qa_mouse_press() {
    local x="$1" y="$2" btn="${3:-0}"
    _qa_mouse_raw "$(printf '\x1b[<%d;%d;%dM' "$btn" "$x" "$y")"
    sleep "${4:-0.05}"
}

qa_mouse_drag() {
    local x="$1" y="$2" btn="${3:-0}"
    _qa_mouse_raw "$(printf '\x1b[<%d;%d;%dM' "$((32 + btn))" "$x" "$y")"
    sleep "${4:-0.05}"
}

qa_mouse_release() {
    local x="$1" y="$2" btn="${3:-0}"
    _qa_mouse_raw "$(printf '\x1b[<%d;%d;%dm' "$btn" "$x" "$y")"
    sleep "${4:-0.05}"
}

qa_mouse_click() {
    local x="$1" y="$2" btn="${3:-0}"
    qa_mouse_press "$x" "$y" "$btn" 0.03
    qa_mouse_release "$x" "$y" "$btn" "${4:-0.05}"
}

# Full drag gesture: press at from, N interpolated motion steps, release at to.
#   qa_mouse_drag_gesture FROM_X FROM_Y TO_X TO_Y [STEPS]
qa_mouse_drag_gesture() {
    local fx="$1" fy="$2" tx="$3" ty="$4" steps="${5:-4}"
    qa_mouse_press "$fx" "$fy" 0 0.05
    local i
    for ((i = 1; i <= steps; i++)); do
        local cx=$(( fx + (tx - fx) * i / steps ))
        local cy=$(( fy + (ty - fy) * i / steps ))
        qa_mouse_drag "$cx" "$cy" 0 0.03
    done
    qa_mouse_release "$tx" "$ty" 0 0.05
}

qa_mouse_scroll() {
    local x="$1" y="$2" dir="$3" n="${4:-1}"
    local btn=64
    [[ "$dir" == "down" ]] && btn=65
    local i
    for ((i = 0; i < n; i++)); do
        _qa_mouse_raw "$(printf '\x1b[<%d;%d;%dM' "$btn" "$x" "$y")"
    done
    sleep "${5:-0.05}"
}

# ---------------------------------------------------------------------------
# Screen capture
# ---------------------------------------------------------------------------

QA_SCREEN=""
qa_screen() {
    QA_SCREEN=$(hangon screen "$QA_SESSION" 2>/dev/null || echo "")
}

# Raw ANSI screen capture (colors/escape codes intact), for tests that
# need to assert an actual visual change (e.g. a theme toggle's color
# values) rather than just text content — `hangon screen` strips escapes.
# hangon's tmux backend names the underlying tmux session "hangon-<PID>"
# where PID is the "Holder PID" reported by `hangon status`.
#   qa_raw_screen SESSION_NAME
# Sets QA_RAW_SCREEN. Returns empty string (not a failure) if the session
# or its tmux pane can't be found, so callers should check for emptiness.
QA_RAW_SCREEN=""
qa_raw_screen() {
    local session="$1"
    local pid
    pid=$(hangon status "$session" 2>/dev/null | awk '/^Holder PID:/ {print $3}')
    if [[ -z "$pid" ]]; then
        QA_RAW_SCREEN=""
        return
    fi
    QA_RAW_SCREEN=$(tmux capture-pane -t "hangon-$pid" -e -p 2>/dev/null || echo "")
}

qa_screenshot() {
    hangon screenshot "$QA_SESSION" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

qa_assert_screen() {
    local pattern="$1"
    local desc="${2:-screen contains '$pattern'}"
    qa_screen
    if echo "$QA_SCREEN" | grep -qE "$pattern"; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Pattern not found: $pattern"
    fi
}

qa_assert_not_screen() {
    local pattern="$1"
    local desc="${2:-screen does not contain '$pattern'}"
    qa_screen
    if echo "$QA_SCREEN" | grep -qE "$pattern"; then
        qa_fail "$desc" "Pattern unexpectedly found: $pattern"
    else
        qa_pass "$desc"
    fi
}

qa_assert_file_exists() {
    local path="$1"
    local desc="${2:-file exists: $path}"
    if [[ -f "$path" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "File not found: $path"
    fi
}

qa_assert_file_contains() {
    local path="$1"
    local pattern="$2"
    local desc="${3:-file '$path' contains '$pattern'}"
    if grep -qE "$pattern" "$path" 2>/dev/null; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Pattern not found in file"
    fi
}

qa_assert_file_not_contains() {
    local path="$1"
    local pattern="$2"
    local desc="${3:-file '$path' does not contain '$pattern'}"
    if grep -qE "$pattern" "$path" 2>/dev/null; then
        qa_fail "$desc" "Pattern unexpectedly found in file"
    else
        qa_pass "$desc"
    fi
}

qa_assert_exit() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-exit code is $expected}"
    if [[ "$actual" -eq "$expected" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Expected exit $expected, got $actual"
    fi
}

qa_assert_exited() {
    local desc="${1:-editor has exited}"
    sleep 0.3
    if qa_alive 2>/dev/null; then
        qa_fail "$desc" "Session still alive"
    else
        qa_pass "$desc"
    fi
}

# ---------------------------------------------------------------------------
# Precise state extraction
# ---------------------------------------------------------------------------

qa_cursor_pos() {
    qa_screen
    local pos
    pos=$(echo "$QA_SCREEN" | tail -2 | grep -oE '[0-9]+:[0-9]+' | head -1 || true)
    if [[ -n "$pos" ]]; then
        QA_CURSOR_LINE="${pos%%:*}"
        QA_CURSOR_COL="${pos##*:}"
    else
        QA_CURSOR_LINE=""
        QA_CURSOR_COL=""
    fi
}

qa_assert_cursor_at() {
    local expected="$1"
    local desc="${2:-cursor at $expected}"
    qa_cursor_pos
    local actual="${QA_CURSOR_LINE}:${QA_CURSOR_COL}"
    if [[ "$expected" == *:* ]]; then
        if [[ "$actual" == "$expected" ]]; then
            qa_pass "$desc"
        else
            qa_fail "$desc" "Expected $expected, got $actual"
        fi
    else
        if [[ "$QA_CURSOR_LINE" == "$expected" ]]; then
            qa_pass "$desc"
        else
            qa_fail "$desc" "Expected line $expected, got $QA_CURSOR_LINE"
        fi
    fi
}

qa_assert_cursor_not_at() {
    local unexpected="$1"
    local desc="${2:-cursor not at line $unexpected}"
    qa_cursor_pos
    if [[ "$QA_CURSOR_LINE" != "$unexpected" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Cursor still at line $unexpected"
    fi
}

qa_status_bar() {
    qa_screen
    QA_STATUS_BAR=$(echo "$QA_SCREEN" | tail -1)
}

# ---------------------------------------------------------------------------
# Results reporting
# ---------------------------------------------------------------------------

qa_pass() {
    echo "  ${_GREEN}PASS${_RESET} $1"
    QA_PASSED=$((QA_PASSED + 1))
}

qa_fail() {
    local desc="$1"
    local detail="${2:-}"
    echo "  ${_RED}FAIL${_RESET} $desc"
    [[ -n "$detail" ]] && echo "       ${_DIM}$detail${_RESET}"
    if [[ -n "$QA_SCREEN" ]]; then
        echo "       ${_DIM}--- screen snapshot ---${_RESET}"
        echo "$QA_SCREEN" | head -5 | sed 's/^/       /'
        echo "       ${_DIM}...${_RESET}"
    fi
    QA_FAILED=$((QA_FAILED + 1))
}

qa_skip() {
    local desc="$1"
    local reason="${2:-}"
    echo "  ${_YELLOW}SKIP${_RESET} $desc${reason:+ ($reason)}"
    QA_SKIPPED=$((QA_SKIPPED + 1))
}

qa_header() {
    echo "${_CYAN}[$QA_TEST_NAME]${_RESET} $1"
}

qa_summary() {
    echo ""
    local total=$((QA_PASSED + QA_FAILED + QA_SKIPPED))
    if [[ $QA_FAILED -eq 0 ]]; then
        echo "${_GREEN}$QA_TEST_NAME: $QA_PASSED passed${_RESET}${QA_SKIPPED:+, $QA_SKIPPED skipped} (of $total)"
    else
        echo "${_RED}$QA_TEST_NAME: $QA_FAILED FAILED${_RESET}, $QA_PASSED passed${QA_SKIPPED:+, $QA_SKIPPED skipped} (of $total)"
    fi
    [[ $QA_FAILED -eq 0 ]]
}

# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

qa_tmpfile() {
    local name="$1"
    local content="${2:-}"
    local path="$QA_TMPDIR/$name"
    mkdir -p "$(dirname "$path")"
    printf '%s' "$content" > "$path"
    echo "$path"
}

qa_tmpfile_nl() {
    local name="$1"
    local content="${2:-}"
    local path="$QA_TMPDIR/$name"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    echo "$path"
}

# ---------------------------------------------------------------------------
# LLM judge (Tier 2)
# ---------------------------------------------------------------------------

qa_llm_available() {
    [[ "${ZEPTO_QA_SKIP_LLM:-0}" != "1" ]] && \
    [[ -n "${ZEPTO_QA_API_KEY:-}${ANTHROPIC_API_KEY:-}${OPENAI_API_KEY:-}" ]]
}

qa_llm_judge() {
    local screenshot="$1"
    local prompt="$2"
    "$_QA_HELPERS_DIR/llm-judge.sh" "$screenshot" "$prompt"
}

qa_assert_visual() {
    local screenshot="$1"
    local prompt="$2"
    local desc="${3:-visual check: $prompt}"

    if ! qa_llm_available; then
        qa_skip "$desc" "LLM not configured"
        return
    fi

    local result
    result=$(qa_llm_judge "$screenshot" "$prompt") || true
    if [[ "$result" == PASS* ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "$result"
    fi
}

# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------
qa_setup
