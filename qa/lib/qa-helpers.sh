#!/usr/bin/env bash
# ===========================================================================
# qa-helpers.sh — shared utilities for Zepto QA test scripts
# ===========================================================================
# Source this at the top of every test script:
#   source "$(dirname "$0")/../../lib/qa-helpers.sh"
# ===========================================================================

set -euo pipefail

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
}

qa_cleanup() {
    hangon stop "$QA_SESSION" 2>/dev/null || true
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
# Isolation is passed as CLI flags, NOT env vars: hangon sessions do NOT
# inherit the client's environment, so the exported ZEPTO_STATE_DIR never
# reached zepto — every test silently shared the user's real state dir
# (and the system clipboard), causing cross-test interference under
# parallel runs. See bugs.md 2026-08-28.
qa_start() {
    hangon start process --name "$QA_SESSION" -- "$QA_ZEPTO" \
        --state-dir "$QA_STATE_DIR" --no-system-clipboard "$@"
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
# Sets QA_PROJECT_DIR. QA_ZEPTO is already absolute.
#
#   qa_project; dir="$QA_PROJECT_DIR"
#   echo "content" > "$dir/file.txt"
#   qa_start file.txt
#
# MUST be called directly, never via command substitution: `$(qa_project)`
# runs in a subshell, so the cd is silently lost and every subsequent
# command — including git init/add/commit in qa_git_repo callers — runs in
# the caller's original directory. That once committed junk into the real
# zepto checkout (see bugs.md 2026-08-28). The guard below turns that
# mistake into a hard abort instead of silent repo pollution.
qa_project() {
    # BASH_SUBSHELL (bash 3.0+; macOS ships 3.2 so BASHPID is unavailable)
    if [[ "${BASH_SUBSHELL:-0}" -gt 0 ]]; then
        echo "FATAL: qa_project/qa_git_repo must be called directly (qa_project; dir=\"\$QA_PROJECT_DIR\"), not via \$(...) or a subshell — the cd would be lost and later commands would run in the caller's directory" >&2
        kill -TERM "$$" 2>/dev/null
        exit 1
    fi
    _QA_PROJECT_DIR=$(mktemp -d /tmp/zepto_qa_proj_XXXXXX)
    cd "$_QA_PROJECT_DIR"
    QA_PROJECT_DIR="$_QA_PROJECT_DIR"
}

# Create a git repo project directory and cd into it (same calling rules
# as qa_project). Initializes git with test user config.
#   qa_git_repo; dir="$QA_PROJECT_DIR"
#   echo "content" > file.txt && git add . && git commit -m "init"
qa_git_repo() {
    qa_project
    # Never git-init where a repo already exists (e.g. the zepto checkout
    # itself) — a -q init there is a silent no-op and the following
    # add/commit would target the real repo.
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "FATAL: qa_git_repo: refusing to init inside existing git repo at $PWD" >&2
        exit 1
    fi
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
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

qa_send() {
    hangon send "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

qa_keys() {
    hangon keys "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

# Send raw escape sequences
qa_raw() {
    hangon send "$QA_SESSION" "$1"
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
    hangon expect "$QA_SESSION" "$pattern" --timeout "$timeout" 2>/dev/null
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
# Screen capture
# ---------------------------------------------------------------------------

QA_SCREEN=""
qa_screen() {
    QA_SCREEN=$(hangon screen "$QA_SESSION" 2>/dev/null || echo "")
}

qa_screenshot() {
    hangon screenshot "$QA_SESSION" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

# Wait (up to TIMEOUT s) for a regex to appear on the RENDERED screen,
# then assert. Prefer this over sleep+qa_assert_screen — fixed sleeps
# flake when the suite runs many sessions in parallel and renders are
# starved. Polls `hangon screen` (the rendered text grid); do NOT use
# `hangon expect` for screen content — it matches the raw output stream,
# where escape sequences interleave between characters, so patterns like
# `\(\)` rarely appear as adjacent bytes.
#   qa_assert_expect PATTERN [DESC] [TIMEOUT]
qa_assert_expect() {
    local pattern="$1"
    local desc="${2:-screen shows '$pattern'}"
    local timeout="${3:-8}"
    if qa_wait_screen "$pattern" "$timeout"; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Pattern did not appear within ${timeout}s: $pattern"
    fi
}

# Poll the rendered screen until PATTERN appears (or TIMEOUT s elapse).
# Returns 0 if it appeared; QA_SCREEN holds the last capture either way.
#   qa_wait_screen PATTERN [TIMEOUT]
qa_wait_screen() {
    local pattern="$1"
    local timeout="${2:-8}"
    local tries=$((timeout * 4))
    local i=0
    while (( i < tries )); do
        qa_screen
        if echo "$QA_SCREEN" | grep -qE "$pattern"; then
            return 0
        fi
        sleep 0.25
        i=$((i + 1))
    done
    return 1
}

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
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "$script_dir/llm-judge.sh" "$screenshot" "$prompt"
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
